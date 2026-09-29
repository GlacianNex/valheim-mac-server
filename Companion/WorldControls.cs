using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using HarmonyLib;
using UnityEngine;

public sealed partial class ManagerRcon {
    private Harmony worldHarmony;
    private static float raidsPausedUntil;
    private float nextWorldCheck;
    private readonly HashSet<long> welcomed = new HashSet<long>();
    private WorldMessages worldMessages = new WorldMessages();
    private bool raidPauseAvailable;
    private void InitializeWorldControls() {
        try {
            worldHarmony = new Harmony("io.github.glaciannex.manager.world");
            worldHarmony.Patch(AccessTools.Method(typeof(RandEventSystem), "SetRandomEvent"), prefix:new HarmonyMethod(typeof(ManagerRcon), nameof(AllowRaid)));
            raidPauseAvailable = true;
        } catch (Exception e) { Logger.LogWarning("Temporary raid pause unavailable: " + e.Message); }
    }
    private static bool AllowRaid(RandomEvent __0) { return __0 == null || Time.realtimeSinceStartup >= raidsPausedUntil; }
    private void UpdateWorldControls() {
        if (Time.realtimeSinceStartup < nextWorldCheck || ZNet.instance == null || !ZNet.instance.IsServer() || ZRoutedRpc.instance == null) return;
        nextWorldCheck = Time.realtimeSinceStartup + 2;
        try {
            var path = Environment.GetEnvironmentVariable("VSM_WORLD_CONTROL_SETTINGS");
            if (!string.IsNullOrEmpty(path) && File.Exists(path)) worldMessages = Deserialize<WorldMessages>(File.ReadAllText(path));
        } catch { /* Keep the last valid settings during an atomic replacement. */ }
        var peers = ZNet.instance.GetPeers().Where(p => p.IsReady() && !p.m_server).ToArray();
        welcomed.IntersectWith(peers.Select(p => p.m_uid));
        foreach (var peer in peers) {
            if (welcomed.Add(peer.m_uid) && ValidMessage(worldMessages.welcome)) {
                ZRoutedRpc.instance.InvokeRoutedRPC(peer.m_uid, "ChatMessage", Vector3.zero, (int)Talker.Type.Shout,
                    new UserInfo { Name="Server", UserId=new Splatform.PlatformUserID("Bot",0,false) }, worldMessages.welcome);
                ZRoutedRpc.instance.InvokeRoutedRPC(peer.m_uid,"ShowMessage",(int)MessageHud.MessageType.Center,worldMessages.welcome);
            }
        }
    }
    private static bool ValidMessage(string text) { return !string.IsNullOrWhiteSpace(text) && text.Length <= 500 && text.IndexOfAny(new [] {'\n','\r','\0'}) < 0; }
    private static T Deserialize<T>(string value) {
        using (var stream = new MemoryStream(System.Text.Encoding.UTF8.GetBytes(value)))
            return (T)new DataContractJsonSerializer(typeof(T)).ReadObject(stream);
    }
    private string WorldCommand(string command) {
        if (EnvMan.instance == null || RandEventSystem.instance == null) return "ERROR: World is not ready";
        var env = EnvMan.instance; var raids = RandEventSystem.instance; var net = ZNet.instance;
        var choices = raids.m_events.Where(e => e.m_enabled && !e.m_devDisabled && e.m_random).Select(e => e.m_name).Distinct().OrderBy(n => n).ToArray();
        if (command == "worldInfo") return Serialize(new WorldInfo {
            day = env.GetDay(), seconds = net.GetTimeSeconds(), dayFraction = env.GetDayFraction(),
            raid = raids.GetCurrentRandomEvent()?.m_name ?? "", raidsPausedSeconds = Math.Max(0, raidsPausedUntil-Time.realtimeSinceStartup),
            raidPauseAvailable = raidPauseAvailable, events = choices,
            players = net.GetPeers().Where(p => p.IsReady() && !p.m_server).Select(Player).ToArray(),
            saveInProgress = net.SaveStartTime > net.SaveDoneTime,
            lastSaveSecondsAgo = net.SaveDoneTime > 0 ? (double?)(Time.realtimeSinceStartup-net.SaveDoneTime) : null
        });
        if (command == "worldSave") {
            if (net.SaveStartTime > net.SaveDoneTime) return "ERROR: A save is already in progress";
            net.Save(false, true, false); return "OK: World save requested";
        }
        if (command == "worldMorning") {
            if (env.IsTimeSkipping()) return "ERROR: Time is already advancing";
            env.SkipToMorning(); return "OK: Advancing to the next morning";
        }
        if (command.StartsWith("worldAdvance ")) {
            if (!int.TryParse(command.Substring(13),out int minutes) || minutes < 1 || minutes > 720) return "ERROR: Choose 1 to 720 in-game minutes";
            if (env.IsTimeSkipping()) return "ERROR: Time is already advancing";
            net.SetNetTime(net.GetTimeSeconds() + minutes * env.m_dayLengthSec / 1440.0);
            return "OK: World time advanced";
        }
        if (command == "worldRaidStop") { raids.ResetRandomEvent(); return "OK: Current raid stopped; existing creatures remain"; }
        if (command == "worldRaidResume") { raidsPausedUntil = 0; return "OK: Normal raid scheduling resumed"; }
        if (command.StartsWith("worldRaidPause ")) {
            if (!raidPauseAvailable) return "ERROR: This server build does not support temporary raid pauses";
            if (!int.TryParse(command.Substring(15),out int minutes) || minutes < 1 || minutes > 120) return "ERROR: Choose 1 to 120 real minutes";
            raidsPausedUntil = Time.realtimeSinceStartup + minutes * 60; return "OK: New raids paused; any current raid continues";
        }
        if (command.StartsWith("worldRaidStart ")) {
            var request = Deserialize<RaidRequest>(command.Substring(15));
            if (Time.realtimeSinceStartup < raidsPausedUntil) return "ERROR: Resume raids before starting one";
            if (raids.GetCurrentRandomEvent() != null) return "ERROR: Stop the current raid first";
            if (!choices.Contains(request.raid)) return "ERROR: Select an available raid";
            var peer = net.GetPeers().FirstOrDefault(p => p.IsReady() && !p.m_server && p.m_socket.GetHostName() == request.player);
            if (peer == null) return "ERROR: That player is no longer connected";
            raids.SetRandomEventByName(request.raid,peer.m_refPos);
            return "OK: Raid started near " + peer.m_playerName;
        }
        return "ERROR: Unsupported world control";
    }
    [DataContract] private class WorldMessages { [DataMember] public string welcome; }
    [DataContract] private class RaidRequest { [DataMember] public string raid; [DataMember] public string player; }
    [DataContract] private class WorldInfo {
        [DataMember] public int day;
        [DataMember] public double seconds;
        [DataMember] public float dayFraction;
        [DataMember] public string raid;
        [DataMember] public float raidsPausedSeconds;
        [DataMember] public bool raidPauseAvailable;
        [DataMember] public string[] events;
        [DataMember] public PlayerInfo[] players;
        [DataMember] public bool saveInProgress;
        [DataMember] public double? lastSaveSecondsAgo;
    }
}
