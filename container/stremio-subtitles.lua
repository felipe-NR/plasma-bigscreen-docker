-- Loads subtitles from Stremio's OpenSubtitles v3 addon into an mpv that
-- Stremio opened as its external player. Stremio hands over only the video
-- URL, so the script finds the title by looking that URL up in the streams
-- Stremio keeps in its local storage, then asks the addon for subtitles the
-- way Stremio does. The tracks are added next to the embedded ones. The first
-- track in the most preferred language is selected when that language ranks
-- above both the subtitle already on and the audio, so an English embedded
-- track gives way to Portuguese, and Portuguese audio gets none.

local utils = require "mp.utils"
local msg = require "mp.msg"

local options = {
    addon = "https://opensubtitles-v3.strem.io",
    server = "http://127.0.0.1:11470",
    -- OpenSubtitles language codes, most preferred first. pob is Brazilian
    -- Portuguese.
    languages = "pob,por,eng",
    per_language = 5,
    -- Stremio writes its local storage a few seconds after it opens the
    -- player, so the lookup is retried.
    lookup_attempts = 15,
    lookup_interval = 2,
}
require("mp.options").read_options(options, "stremio-subtitles")

-- mpv language tags for the OpenSubtitles codes.
local language_tags = { pob = "pt-BR", por = "pt", eng = "en", spa = "es", fre = "fr", ger = "de", ita = "it", jpn = "ja" }

local function language_tag(code)
    return language_tags[code] or code
end

local function base_language(tag)
    tag = language_tag(tag or "")
    return tag:sub(1, 2):lower()
end

local function encode(value)
    return (value:gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", c:byte())
    end))
end

local function run(args)
    local result = mp.command_native({
        name = "subprocess",
        args = args,
        capture_stdout = true,
        capture_stderr = true,
        playback_only = false,
    })
    if result.status ~= 0 then
        msg.debug(args[1] .. " failed: " .. (result.stderr or ""))
        return nil
    end
    return result.stdout
end

local function fetch_json(url, callback)
    mp.command_native_async({
        name = "subprocess",
        args = { "curl", "-sf", "-m", "20", url },
        capture_stdout = true,
        playback_only = false,
    }, function(success, result)
        if success and result.status == 0 then
            callback(utils.parse_json(result.stdout))
        else
            callback(nil)
        end
    end)
end

local function storage_path()
    local root = utils.join_path(os.getenv("HOME") or "", ".local/share/stremio/storage")
    for _, first in ipairs(utils.readdir(root, "dirs") or {}) do
        local level = utils.join_path(root, first)
        for _, second in ipairs(utils.readdir(level, "dirs") or {}) do
            local db = utils.join_path(utils.join_path(level, second), "LocalStorage/localstorage.sqlite3")
            if utils.file_info(db) then
                return db
            end
        end
    end
end

-- WebKit keeps local storage values as UTF-16 blobs. writefile copies the
-- bytes unchanged, and iconv turns them into the UTF-8 that parse_json reads.
local function read_streams(db)
    local blob = utils.join_path(os.getenv("XDG_RUNTIME_DIR") or "/tmp", "stremio-subtitles-streams.bin")
    local query = "select writefile('" .. blob .. "', value) from ItemTable where key = 'streams'"
    if not run({ "sqlite3", "-readonly", db, query }) then
        return nil
    end
    local json = run({ "iconv", "-f", "UTF-16LE", "-t", "UTF-8", blob })
    os.remove(blob)
    return json and utils.parse_json(json)
end

local function find_stream(url)
    local db = storage_path()
    local streams = db and read_streams(db)
    for _, pair in ipairs(streams and streams.items or {}) do
        local entry = pair[2]
        if entry and entry.stream and entry.stream.url == url then
            return entry
        end
    end
end

-- Position of a language in the preference list; languages left out of it
-- rank last.
local function rank(base)
    local position = 0
    for code in options.languages:gmatch("[^,%s]+") do
        position = position + 1
        if base_language(code) == base then
            return position
        end
    end
    return math.huge
end

local function add_subtitles(subtitles)
    local current = mp.get_property_native("current-tracks/sub")
    local audio = base_language(mp.get_property("current-tracks/audio/lang"))
    local limit = math.min(rank(audio), current and rank(base_language(current.lang)) or math.huge)
    local select_next = true
    local counts = {}

    for code in options.languages:gmatch("[^,%s]+") do
        local added = 0
        for _, sub in ipairs(subtitles) do
            if sub.lang == code and sub.url and added < options.per_language then
                added = added + 1
                local flags = "auto"
                if select_next and rank(base_language(code)) < limit then
                    flags = "select"
                    select_next = false
                end
                mp.command_native_async({
                    name = "sub-add",
                    url = sub.url,
                    flags = flags,
                    title = string.format("OpenSubtitles %s %d", language_tag(code), added),
                    lang = language_tag(code),
                }, function() end)
            end
        end
        if added > 0 then
            counts[#counts + 1] = string.format("%d %s", added, language_tag(code))
        end
    end

    if #counts > 0 then
        mp.osd_message("OpenSubtitles: " .. table.concat(counts, ", "), 4)
    else
        msg.info("no subtitles in the preferred languages")
    end
end

local function request_subtitles(url, entry)
    local function query(extra)
        local address = string.format("%s/subtitles/%s/%s%s.json",
            options.addon, entry.type, encode(entry.videoId), extra and ("/" .. extra) or "")
        fetch_json(address, function(reply)
            if reply and reply.subtitles then
                add_subtitles(reply.subtitles)
            else
                msg.warn("the subtitle addon did not answer")
            end
        end)
    end

    -- The video hash lets the addon put subtitles synced to this release
    -- first. Stremio's streaming server computes it, and runs only while
    -- Stremio is open, so the query goes ahead without it when it fails.
    fetch_json(options.server .. "/opensubHash?videoUrl=" .. encode(url), function(reply)
        local hash = reply and reply.result
        if hash and hash.hash and hash.size then
            local filename = entry.stream.behaviorHints and entry.stream.behaviorHints.filename
            local extra = string.format("videoHash=%s&videoSize=%s", encode(hash.hash), encode(tostring(hash.size)))
            if filename then
                extra = extra .. "&filename=" .. encode(filename)
            end
            query(extra)
        else
            query(nil)
        end
    end)
end

local function lookup(url, attempt)
    if mp.get_property("path") ~= url then
        return
    end
    local entry = find_stream(url)
    if entry and entry.type and entry.videoId then
        msg.info("Stremio stream " .. entry.videoId)
        request_subtitles(url, entry)
    elseif attempt < options.lookup_attempts then
        mp.add_timeout(options.lookup_interval, function()
            lookup(url, attempt + 1)
        end)
    else
        msg.info("not a stream Stremio opened")
    end
end

mp.register_event("file-loaded", function()
    local url = mp.get_property("path") or ""
    if url:find("^https?://") then
        lookup(url, 1)
    end
end)
