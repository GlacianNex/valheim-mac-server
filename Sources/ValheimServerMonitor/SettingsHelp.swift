import AppKit

enum SettingsHelp {
    static let fields: [String:String] = [
        "label":"A unique name shown only in this monitor. Changing it does not rename your world or change the public server name.",
        "name":"The name players see in Valheim's server browser. It must not contain the server password.",
        "world":"Optional for a fresh world: leave blank to generate a filename from the profile name (for example, Friday Vikings becomes Friday_Vikings). You can enter your own filename instead. For imports, use the save's folder name or .db/.fwl filename without its extension. New profiles have separate save folders. Existing world filenames are locked to prevent accidental world changes. For a chosen seed, create a world in Valheim and import it.",
        "password":"Optional for unlisted servers: blank means anyone with the address or join code can connect without a password. Listed servers require at least 5 characters. Stored in the local profile file and supplied to Valheim at startup.",
        "port":"UDP base port, 1–65534; Valheim also uses the following port. Default: 2456 and 2457. Steam-only remote play requires forwarding both ports to this Mac.",
        "public":"Checked: advertise in the server browser. Unchecked: hide from the list; direct connections remain possible. This is not an access-control setting.",
        "crossplay":"Checked: use PlayFab relay and allow supported platforms; no router forwarding is normally needed. Use a join code or public address, not LAN/loopback IP. Unchecked: use Steam networking; Steam clients only.",
        "instanceid":"Optional PlayFab instance identifier. Each running server must use a different UDP port pair. An instance ID can additionally distinguish PlayFab servers on the same machine/network; leave blank unless you need an explicit identifier.",
        "saveinterval":"Seconds between automatic world saves. Default 1800 = 30 minutes. A clean Save & Stop also saves the world. Shorter intervals can create more frequent disk activity.",
        "backups":"Number of automatic world backups retained by Valheim. Default 4; these are separate from ordinary saves.",
        "backupshort":"Interval for the short-term backup, in seconds. Default 7200 = 2 hours.",
        "backuplong":"Interval for the longer-term backups, in seconds. Default 43200 = 12 hours.",
        "preset":"A bundle of world settings applied before the individual overrides below. Normal resets modifiers to baseline; Keep world settings adds no preset. Presets can change existing saved settings. Some modifiers affect achievement eligibility; check Valheim's current warning.",
        "Combat":"Damage figures are relative to Normal. Harder settings also affect enemy speed/size and level-up chances. Keep world / preset value does not reset an existing modifier. Normal baseline: player damage 100%, enemy damage 100%.",
        "DeathPenalty":"Skill loss is a percentage of current skill levels. Dropped items remain recoverable; destroyed items do not. Normal baseline: drop all carried items and lose 5% skills. Keep world / preset value preserves the applicable saved/preset setting.",
        "Resources":"Resource quantity relative to the normal 1× rate. Eligible drops can round up, so 1.5× is not always an exact per-drop ratio. Fish, trophies, and boss drops are exceptions. Keep world / preset value preserves the saved/preset rate.",
        "Raids":"These are approximate eligibility-check intervals and chances per check, not guaranteed time between raids. Player location and event requirements still apply. Normal: about 46 minutes, 20% chance. Disabling random raids does not remove ordinary nighttime enemies.",
        "Portals":"Controls item transport and portal availability. Keep world / preset value preserves saved/preset rules. Normal portals restrict some items such as metals, subject to portal type.",
        "nobuildcost":"Enables building without spending construction materials. Recipes still need to be discovered. Unchecked sends no override; it does not clear a flag already saved in the world.",
        "playerevents":"Uses individual player progression to determine eligible raids instead of shared world progression. Unchecked sends no override; it does not clear an existing saved flag.",
        "passivemobs":"Enemies generally wait to be provoked before attacking. Unchecked sends no override; it does not clear an existing saved flag.",
        "fire":"Enables spreading fire hazards outside the Ashlands, including flammable wooden structures. Unchecked adds no override and does not clear an existing world flag.",
        "nomap":"Disables the world map and minimap. Unchecked sends no override; it does not clear an existing saved flag.",
        "admins":"Platform user IDs that receive admin privileges. Use the exact IDs from F2 or server logs. Separate entries with commas or newlines. This does not bypass the permitted/banned lists.",
        "banned":"Platform user IDs blocked from connecting. Separate entries with commas or newlines. Leave blank for no explicit bans.",
        "permitted":"Whitelist: if any IDs are listed, everyone else is excluded. Separate entries with commas or newlines. Blank allows anyone who has the password, except banned players.",
        "extra":"Additional server arguments not covered by this form. Quote values containing spaces. These are passed as arguments, not shell commands. Managed options cannot be duplicated. Unsupported flags may be ignored by Valheim."
    ]
    static let titles: [String:[String:String]] = [
        "Resources":["muchless":"0.5× resources — half","less":"0.75× resources — three quarters","more":"1.5× resources","muchmore":"2× resources — double","most":"3× resources — triple"],
        "Combat":["veryeasy":"Very Easy — you 125%, enemies 50%","easy":"Easy — you 110%, enemies 75%","hard":"Hard — you 85%, enemies 150%","veryhard":"Very Hard — you 70%, enemies 200%"],
        "DeathPenalty":["casual":"Casual — keep equipped; lose 1% skills","veryeasy":"Very Easy — drop items; lose 1% skills","easy":"Easy — drop items; lose 2.5% skills","hard":"Hard — destroy unequipped; lose 7.5%","hardcore":"Hardcore — destroy items; lose all skills"],
        "Raids":["none":"No random raids","muchless":"Much Less — ~92 min checks, 10%","less":"Less — ~69 min checks, 13.33%","more":"More — ~28 min checks, 33.33%","muchmore":"Much More — ~14 min checks, 66.67%"],
        "Portals":["casual":"Allow restricted items, including metals","hard":"Disable portals when a boss is active","veryhard":"Disable all portals"],
        "preset":["Normal":"Normal — reset to standard rules","Casual":"Casual — relaxed survival","Easy":"Easy — easier combat and deaths","Hard":"Hard — tougher combat and deaths","Hardcore":"Hardcore — permanent death losses","Immersive":"Immersive — no map or portals","Hammer":"Hammer — building without material costs"]
    ]
    static func savedTitle(_ key: String, _ raw: String) -> String {
        if raw == "default" {
            return ["Combat":"Normal — 100% damage", "DeathPenalty":"Normal — 5% skill loss", "Resources":"1× resources", "Raids":"Normal", "Portals":"Normal item restrictions"][key] ?? "Normal"
        }
        return title(key, raw)
    }
    static func title(_ key:String,_ raw:String)->String {
        if raw.isEmpty {return key=="preset" ? "Keep world settings (no preset)" : "Keep world / preset value"}
        let compact: [String:[String:String]] = [
            "DeathPenalty":["casual":"Casual — 1% skill loss","veryeasy":"Very Easy — 1% skill loss","easy":"Easy — 2.5% skill loss","hard":"Hard — 7.5% skill loss","hardcore":"Hardcore — 100% skill loss"],
            "Combat":["veryeasy":"Very Easy","easy":"Easy","hard":"Hard","veryhard":"Very Hard"],
            "Raids":["none":"None","muchless":"Much Less","less":"Less","more":"More","muchmore":"Much More"],
            "preset":["Normal":"Normal","Casual":"Casual","Easy":"Easy","Hard":"Hard","Hardcore":"Hardcore","Immersive":"Immersive","Hammer":"Hammer"]
        ]
        return compact[key]?[raw] ?? titles[key]?[raw] ?? raw
    }
    static func fieldHelp(_ key:String)->String {
        let order: [String:[String]] = [
            "preset":["Normal","Casual","Easy","Hard","Hardcore","Immersive","Hammer"],
            "Combat":["veryeasy","easy","hard","veryhard"],
            "DeathPenalty":["casual","veryeasy","easy","hard","hardcore"],
            "Resources":["muchless","less","more","muchmore","most"],
            "Raids":["none","muchless","less","more","muchmore"],
            "Portals":["casual","hard","veryhard"]
        ]
        let base=fields[key] ?? ""
        if key=="DeathPenalty" {
            return base + "\n\nCasual: keep equipped gear, drop other inventory; 1% skill loss.\nVery Easy: drop equipped gear and inventory; 1% skill loss.\nEasy: drop equipped gear and inventory; 2.5% skill loss.\nHard: drop equipped gear, destroy unequipped inventory; 7.5% skill loss.\nHardcore: destroy all carried gear/items; reset skills to zero."
        }
        guard let values=order[key] else {return base}
        return base + "\n\n" + values.map{titles[key]?[$0] ?? $0}.joined(separator:"\n")
    }
    static func optionHelp(_ key:String,_ raw:String)->String {
        let extra: [String:String] = [
            "Combat:veryeasy":"Player damage 1.25×; enemy damage 0.5×; enemy speed/size 0.9×.",
            "Combat:easy":"Player damage 1.10×; enemy damage 0.75×; enemy speed/size 0.9×.",
            "Combat:hard":"Player damage 0.85×; enemy damage 1.5×; enemy speed/size 1.1×; enemy level-up factor 1.2×.",
            "Combat:veryhard":"Player damage 0.70×; enemy damage 2×; enemy speed/size 1.2×; enemy level-up factor 1.4×.",
            "DeathPenalty:casual":"Keep equipped gear. Other inventory drops at death. Lose 1% of skill levels.",
            "DeathPenalty:hard":"Equipped items drop and can be recovered. Unequipped inventory is destroyed. Lose 7.5% of skill levels.",
            "DeathPenalty:hardcore":"All carried/equipped items are destroyed and skills reset. Buildings and stored world items are not deleted."
        ]
        return (extra[key+":"+raw].map{$0+"\n\n"} ?? "") + (fields[key] ?? "")
    }
}
