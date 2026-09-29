using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using Mono.Cecil;
using System.IO;
using System.Linq;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using BepInEx;
using BepInEx.Bootstrap;
using BepInEx.Logging;
using UnityEngine;

public sealed partial class ManagerRcon
{
    private ModLogListener modLog;
    private float nextModSnapshot;
    private List<ModState> discoveredMods;
    private sealed class ModLogListener : ILogListener
    {
        public readonly ConcurrentDictionary<string, string> Errors = new ConcurrentDictionary<string, string>();
        public void LogEvent(object sender, LogEventArgs args)
        {
            if ((args.Level & (LogLevel.Error | LogLevel.Fatal)) == 0) return;
            var text = Convert.ToString(args.Data) ?? "";
            Errors[args.Source.SourceName] = text.Length > 2000 ? text.Substring(0, 2000) : text;
        }
        public void Dispose() { }
    }
    [DataContract] private sealed class ModSnapshot
    {
        [DataMember] public int pid;
        [DataMember] public string updated;
        [DataMember] public ModState[] mods;
    }
    [DataContract] private sealed class ModState
    {
        [DataMember] public string guid;
        [DataMember] public string name;
        [DataMember] public string version;
        [DataMember] public string path;
        [DataMember] public string status;
        [DataMember] public string error;
        [DataMember] public string[] dependencies;
        [DataMember] public string kind;
        [DataMember] public string[] patcherTypes;
    }
    private void InitializeModStatus()
    {
        modLog = new ModLogListener();
        BepInEx.Logging.Logger.Listeners.Add(modLog);
    }
    private ModState[] ReadModStates()
    {
        if (discoveredMods == null) {
            discoveredMods = new List<ModState>();
            foreach (var file in Directory.GetFiles(Paths.PluginPath, "*.dll", SearchOption.AllDirectories)) {
                try {
                    // Cecil reads metadata; it does not execute the DLL's code.
                    using (var resolver = new DefaultAssemblyResolver()) {
                        resolver.AddSearchDirectory(Paths.BepInExAssemblyDirectory); resolver.AddSearchDirectory(Paths.ManagedPath); resolver.AddSearchDirectory(Path.GetDirectoryName(file));
                    using (var assembly = AssemblyDefinition.ReadAssembly(file, new ReaderParameters { AssemblyResolver = resolver })) {
                        bool hasPlugin = false;
                        foreach (var type in assembly.MainModule.Types) {
                            var attr = type.CustomAttributes.FirstOrDefault(a => a.AttributeType.FullName == "BepInEx.BepInPlugin");
                            if (attr == null || attr.ConstructorArguments.Count < 3) continue;
                            hasPlugin = true;
                            discoveredMods.Add(new ModState { guid = (string)attr.ConstructorArguments[0].Value,
                                name = (string)attr.ConstructorArguments[1].Value, version = (string)attr.ConstructorArguments[2].Value,
                                path = file, dependencies = type.CustomAttributes.Where(a => a.AttributeType.FullName == "BepInEx.BepInDependency")
                                    .Select(a => String.Join(" ", a.ConstructorArguments.Select(v => Convert.ToString(v.Value)))).ToArray() });
                        }
                        if (!hasPlugin) discoveredMods.Add(new ModState { guid = assembly.Name.Name, name = assembly.Name.Name,
                            version = assembly.Name.Version.ToString(), path = file, kind = "library", dependencies = new string[0] });
                    }
                    }
                } catch { /* Native/support DLLs are not necessarily BepInEx plugins. */ }
            }
        }
        if (Directory.Exists(Paths.PatcherPluginPath)) {
            foreach (var file in Directory.GetFiles(Paths.PatcherPluginPath, "*.dll", SearchOption.AllDirectories)) {
                if (discoveredMods.Any(m => m.path == file)) continue;
                try {
                    using (var assembly = AssemblyDefinition.ReadAssembly(file)) {
                        // Match BepInEx 5's patcher contract without executing the assembly.
                        var types = assembly.MainModule.Types.Where(t =>
                            t.Methods.Any(m => m.Name == "get_TargetDLLs" && m.IsPublic && m.IsStatic && m.ReturnType.FullName == "System.Collections.Generic.IEnumerable`1<System.String>") &&
                            t.Methods.Any(m => m.Name == "Patch" && m.IsPublic && m.IsStatic && m.ReturnType.FullName == "System.Void" && m.Parameters.Count == 1 &&
                                (m.Parameters[0].ParameterType.FullName == "Mono.Cecil.AssemblyDefinition" || m.Parameters[0].ParameterType.FullName == "Mono.Cecil.AssemblyDefinition&")))
                            .Select(t => t.FullName).ToArray();
                        if (types.Length > 0) discoveredMods.Add(new ModState { guid = assembly.Name.Name, name = assembly.Name.Name,
                            version = assembly.Name.Version.ToString(), path = file, dependencies = new string[0], kind = "patcher", patcherTypes = types });
                    }
                } catch { /* Unreadable files are not proof of a loaded patcher. */ }
            }
        }
        foreach (var info in Chainloader.PluginInfos.Values) {
            if (!discoveredMods.Any(m => m.guid == info.Metadata.GUID && m.path == info.Location)) {
                discoveredMods.Add(new ModState { guid = info.Metadata.GUID, name = info.Metadata.Name,
                    version = info.Metadata.Version.ToString(), path = info.Location,
                    dependencies = info.Dependencies.Select(d => d.DependencyGUID).ToArray() });
            }
        }
        foreach (var item in discoveredMods) {
            if (item.kind == "library") {
                bool referenced = AppDomain.CurrentDomain.GetAssemblies().Any(a => {
                    try { return !a.IsDynamic && Path.GetFullPath(a.Location) == Path.GetFullPath(item.path); } catch { return false; }
                });
                item.status = referenced ? "Loaded" : "Awaiting assembly evidence"; item.error = ""; continue;
            }
            if (item.kind == "patcher") { item.status = "Awaiting preloader evidence"; item.error = ""; continue; }
            BepInEx.PluginInfo info;
            string error;
            modLog.Errors.TryGetValue(item.name, out error);
            var failure = Chainloader.DependencyErrors.FirstOrDefault(e => e.Contains("[" + item.name + " " + item.version + "]"));
            bool loaded = Chainloader.PluginInfos.TryGetValue(item.guid, out info) && info.Instance != null && info.Location == item.path;
            item.error = failure ?? error ?? "";
            item.status = failure != null ? "Failed" : loaded ? String.IsNullOrEmpty(error) ? "Loaded" : "Loaded · Errors" : "Not loaded";
        }
        return discoveredMods.ToArray();
    }
    private void UpdateModStatus()
    {
        if (Time.realtimeSinceStartup < nextModSnapshot) return;
        nextModSnapshot = Time.realtimeSinceStartup + 5;
        try
        {
            var snapshot = new ModSnapshot {
                pid = System.Diagnostics.Process.GetCurrentProcess().Id,
                updated = DateTime.UtcNow.ToString("o"),
                mods = ReadModStates()

            };
            var file = Path.Combine(Paths.ConfigPath, "vsm-mod-status.json");
            var temporary = file + ".tmp";
            using (var stream = File.Create(temporary)) new DataContractJsonSerializer(typeof(ModSnapshot)).WriteObject(stream, snapshot);
            UnityEngine.Debug.Log("VSM mod status: " + File.ReadAllText(temporary));
            if (File.Exists(file)) File.Delete(file);
            File.Move(temporary, file);
        }
        catch { /* Reporting must never interrupt gameplay. */ }
    }
}
