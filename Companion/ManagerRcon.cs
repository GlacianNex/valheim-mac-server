using BepInEx;
using System;
using System.Collections.Concurrent;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Threading;
using System.Threading.Tasks;
using UnityEngine;

// Manager-owned management bridge. No gameplay patches or gameplay-editing commands.
[BepInPlugin("io.github.glaciannex.manager.rcon", "Manager RCON", "1.1.0")]
public sealed class ManagerRcon : BaseUnityPlugin
{
    private TcpListener listener;
    private readonly ConcurrentQueue<Action> pending = new ConcurrentQueue<Action>();
    private readonly CancellationTokenSource stopping = new CancellationTokenSource();
    private string password;
    private int port;
    private int clients;
    private bool attempted;
    private float frameSeconds;
    private string endpointPath;

    private void Awake()
    {
        password = Config.Bind("Connection", "Password", "", "Manager-generated local credential").Value;
        port = Config.Bind("Connection", "Port", 0, "0 selects an unused local port").Value;
        endpointPath = Path.Combine(Paths.ConfigPath, "manager-rcon-endpoint.json");
        if (File.Exists(endpointPath)) File.Delete(endpointPath);
    }
    private void Update()
    {
        frameSeconds = frameSeconds == 0 ? Time.unscaledDeltaTime : frameSeconds * 0.95f + Time.unscaledDeltaTime * 0.05f;
        // Runs for both loaded and newly generated worlds; no LoadWorld patch required.
        if (!attempted && ZNet.instance != null && ZNet.instance.IsServer() && Game.instance != null)
        {
            attempted = true;
            if (password.Length < 32) { Logger.LogError("Manager credential missing; RCON disabled"); return; }
            try
            {
                listener = new TcpListener(IPAddress.Loopback, port);
                listener.Start(4);
                int actual = ((IPEndPoint)listener.LocalEndpoint).Port;
                File.WriteAllText(endpointPath, "{\"port\":" + actual + ",\"pid\":" + System.Diagnostics.Process.GetCurrentProcess().Id + ",\"version\":\"1.0.0\"}");
                Logger.LogInfo("Manager RCON ready on localhost:" + actual);
                Task.Run((Action)Accept);
            }
            catch (Exception e) { Logger.LogError("Manager RCON startup failed: " + e.Message); }
        }
        for (int n = 0; n < 8 && pending.TryDequeue(out var action); n++) action();
    }
    private void Accept()
    {
        while (!stopping.IsCancellationRequested)
        {
            try
            {
                var client = listener.AcceptTcpClient();
                if (Interlocked.Increment(ref clients) > 4) { Interlocked.Decrement(ref clients); client.Close(); continue; }
                Task.Run(() => { try { Serve(client); } finally { client.Close(); Interlocked.Decrement(ref clients); } });
            }
            catch (SocketException) { break; }
            catch (ObjectDisposedException) { break; }
        }
    }
    private static byte[] Read(Stream s, int length)
    {
        var b = new byte[length]; int offset = 0;
        while (offset < length) { int n = s.Read(b, offset, length-offset); if (n == 0) throw new EndOfStreamException(); offset += n; }
        return b;
    }
    private static void Reply(Stream s, int id, int type, string value)
    {
        var text = Encoding.UTF8.GetBytes(value);
        using (var writer = new BinaryWriter(s, Encoding.UTF8, true))
        { writer.Write(text.Length + 10); writer.Write(id); writer.Write(type); writer.Write(text); writer.Write((short)0); writer.Flush(); }
    }
    private void Serve(TcpClient client)
    {
        client.ReceiveTimeout = 5000; client.SendTimeout = 5000;
        try
        {
            using (var stream = client.GetStream())
            {
                bool authenticated = false;
                while (!stopping.IsCancellationRequested)
                {
                    int size = BitConverter.ToInt32(Read(stream,4),0);
                    if (size < 10 || size > 4096) return;
                    var packet = Read(stream,size);
                    if (packet[size-1] != 0 || packet[size-2] != 0) return;
                    int id = BitConverter.ToInt32(packet,0), type = BitConverter.ToInt32(packet,4);
                    string text = Encoding.UTF8.GetString(packet,8,size-10);
                    if (!authenticated)
                    {
                        if (type != 3 || text != password) { Reply(stream,-1,2,"Authentication failed"); return; }
                        authenticated = true; Reply(stream,id,2,"Authenticated"); continue;
                    }
                    if (type != 2) return;
                    var result = new TaskCompletionSource<string>();
                    pending.Enqueue(() => { if (!result.Task.IsCompleted) { try { result.TrySetResult(Execute(text)); } catch (Exception e) { result.TrySetResult("ERROR: " + e.Message); } } });
                    if (!result.Task.Wait(5000)) { result.TrySetCanceled(); return; }
                    Reply(stream,id,0,result.Task.Result);
                }
            }
        }
        catch (IOException) { }
        catch (SocketException) { }
        catch (ObjectDisposedException) { }
    }
    private string Execute(string command)
    {
        if (ZNet.instance == null || !ZNet.instance.IsServer() || ZRoutedRpc.instance == null) return "ERROR: Server is not ready";
        if (command == "health") return "OK ManagerRcon 1.1.0";
        if (command == "players") return "Online " + ZNet.instance.GetPlayerList().Count;
        if (command == "banned") return Serialize(new BanInfo { entries = ZNet.instance.Banned.ToArray() });
        if (command == "serverInfo")
        {
            return Serialize(new ServerInfo {
                version = global::Version.GetVersionString(), players = ZNet.instance.GetPlayerList().Count,
                fps = frameSeconds > 0 ? 1f / frameSeconds : 0,
                managedMemoryBytes = GC.GetTotalMemory(false), uptimeSeconds = Time.realtimeSinceStartup,
                onlinePlayers = ZNet.instance.GetPeers().Where(p => p.IsReady() && !p.m_server).Select(Player).ToArray(),
                banned = ZNet.instance.Banned.ToArray()
            });
        }
        if (command.StartsWith("kick ")) { ZNet.instance.Kick(command.Substring(5)); return "OK: Kick requested"; }
        if (command.StartsWith("ban ")) { ZNet.instance.Ban(command.Substring(4)); return "OK: Ban requested"; }
        if (command.StartsWith("unban ")) { ZNet.instance.Unban(command.Substring(6)); return "OK: Unban requested"; }
        if (command.StartsWith("say "))
        {
            ZRoutedRpc.instance.InvokeRoutedRPC(ZRoutedRpc.Everybody, "ChatMessage", Vector3.zero, (int)Talker.Type.Shout,
                new UserInfo { Name = "Server", UserId = new Splatform.PlatformUserID("Bot",0,false) }, command.Substring(4));
            return "OK";
        }
        if (command.StartsWith("showMessage "))
        {
            ZRoutedRpc.instance.InvokeRoutedRPC(ZRoutedRpc.Everybody, "ShowMessage", (int)MessageHud.MessageType.Center, command.Substring(12));
            return "OK";
        }
        return "ERROR: Unsupported command";
    }
    // Unity's native serializer can omit collection fields on injected plugin types.
    // Use the managed serializer so empty and populated arrays have the same schema.
    private static string Serialize<T>(T value) {
        using (var stream = new MemoryStream()) {
            new DataContractJsonSerializer(typeof(T)).WriteObject(stream, value);
            return Encoding.UTF8.GetString(stream.ToArray());
        }
    }
    private static PlayerInfo Player(ZNetPeer peer) {
        return new PlayerInfo { name = peer.m_playerName, id = peer.m_socket.GetHostName() };
    }
    [DataContract] private class PlayerInfo { [DataMember] public string name; [DataMember] public string id; }
    [DataContract] private class BanInfo { [DataMember] public string[] entries; }
    [DataContract] private class ServerInfo {
        [DataMember] public string version;
        [DataMember] public PlayerInfo[] onlinePlayers;
        [DataMember] public string[] banned;
        [DataMember] public int players;
        [DataMember] public float fps;
        [DataMember] public long managedMemoryBytes;
        [DataMember] public float uptimeSeconds;
    }
    private void OnDestroy()
    {
        stopping.Cancel(); listener?.Stop();
        if (File.Exists(endpointPath)) File.Delete(endpointPath);
    }
}
