dofile("table_show.lua")
dofile("urlcode.lua")
JSON = (loadfile "JSON.lua")()
local urlparse = require("socket.url")
local http = require("socket.http")

local item_value = os.getenv('item_value')
local item_type = os.getenv('item_type')
local item_dir = os.getenv('item_dir')
local warc_file_base = os.getenv('warc_file_base')

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

load_json_file = function(file)
  if file then
    return JSON:decode(file)
  else
    return nil
  end
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

allowed = function(url, parenturl)
  if string.match(urlparse.unescape(url), "[<>\\%*%$;%^%[%],%(%){}]") then
    return false
  end

  local tested = {}
  for s in string.gmatch(url, "([^/]+)") do
    if tested[s] == nil then
      tested[s] = 0
    end
    if tested[s] == 6 then
      return false
    end
    tested[s] = tested[s] + 1
  end

  if url == "https://samsungvr.com/graphql" then
    return true
  end

  for s in string.gmatch(url, "([a-zA-Z0-9]+)") do
    if s == item_value then
      return true
    end
  end

  return false
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]

  if (downloaded[url] ~= true and addedtolist[url] ~= true)
    and allowed(url, parent["url"]) then
    addedtolist[url] = true
    return true
  end
  
  return false
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil
  
  downloaded[url] = true

  local function check(urla)
    local origurl = url
    local url = string.match(urla, "^([^#]+)")
    local url_ = string.match(url, "^(.-)%.?$")
    url_ = string.gsub(url_, "&amp;", "&")
    url_ = string.match(url_, "^(.-)%s*$")
    url_ = string.match(url_, "^(.-)%??$")
    url_ = string.match(url_, "^(.-)&?$")
    if (downloaded[url_] ~= true and addedtolist[url_] ~= true)
      and allowed(url_, origurl) then
      table.insert(urls, { url=url_ })
      addedtolist[url_] = true
      addedtolist[url] = true
    end
  end

  local function checknewurl(newurl)
    if string.match(newurl, "^https?:////") then
      check(string.gsub(newurl, ":////", "://"))
    elseif string.match(newurl, "^https?://") then
      check(newurl)
    elseif string.match(newurl, "^https?:\\/\\?/") then
      check(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^\\/") then
      checknewurl(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^//") then
      check(urlparse.absolute(url, newurl))
    elseif string.match(newurl, "^/") then
      check(urlparse.absolute(url, newurl))
    elseif string.match(newurl, "^%.%./") then
      if string.match(url, "^https?://[^/]+/[^/]+/") then
        check(urlparse.absolute(url, newurl))
      else
        checknewurl(string.match(newurl, "^%.%.(/.+)$"))
      end
    elseif string.match(newurl, "^%./") then
      check(urlparse.absolute(url, newurl))
    end
  end

  local function checknewshorturl(newurl)
    if string.match(newurl, "^%?") then
      check(urlparse.absolute(url, newurl))
    elseif not (string.match(newurl, "^https?:\\?/\\?//?/?")
        or string.match(newurl, "^[/\\]")
        or string.match(newurl, "^%./")
        or string.match(newurl, "^[jJ]ava[sS]cript:")
        or string.match(newurl, "^[mM]ail[tT]o:")
        or string.match(newurl, "^vine:")
        or string.match(newurl, "^android%-app:")
        or string.match(newurl, "^ios%-app:")
        or string.match(newurl, "^%${")) then
      check(urlparse.absolute(url, newurl))
    end
  end

  local function graphql_request(json_data)
    table.insert(urls, {
      url="https://samsungvr.com/graphql",
      post_data=JSON:encode(json_data),
      headers={
        ["content-type"]="application/json"
      }
    })
  end

  if allowed(url, nil) and status_code == 200 then
    html = read_file(file)
    if url == "https://samsungvr.com/view/" .. item_value then
      graphql_request({
        ["operationName"]="video",
        ["variables"]={
            ["id"]=item_value,
            ["commentFirst"]=30,
            ["commentOffset"]=0,
            ["recommentFirst"]=1,
            ["recommentOffset"]=0
        },
        ["query"]="query video($id: String!, $commentFirst: Int!, $commentOffset: Int) {\n  video(id: $id) {\n    ...VideoFragmentV3\n    downloadableVideo {\n      url\n      fileSize\n      resolutionHorizontal\n      resolutionVertical\n      __typename\n    }\n    reaction(sla: Factual) {\n      mine\n      __typename\n    }\n    audioType\n    isInteractive\n    isLiveStream\n    isEncrypted\n    liveStartScheduled\n    author {\n      ...UserFragmentV4\n      __typename\n    }\n    categories {\n      id\n      name\n      __typename\n    }\n    tags {\n      name\n      __typename\n    }\n    extraDates {\n      published\n      __typename\n    }\n    comments(first: $commentFirst, offset: $commentOffset) {\n      totalCount\n      nodes {\n        ...CommentFragmentV1\n        replies(first: 1, offset: 0) {\n          totalCount\n          nodes {\n            ...CommentFragmentV1\n            __typename\n          }\n          __typename\n        }\n        __typename\n      }\n      __typename\n    }\n    recommendedVideos(count: 8) {\n      ...VideoFragmentV3\n      __typename\n    }\n    __typename\n  }\n}\n\nfragment VideoFragmentV3 on Video {\n  ...VideoFragmentV2\n  defaultDate\n  commentCount(sla: Factual)\n  reaction(sla: Factual) {\n    like\n    dislike\n    __typename\n  }\n  __typename\n}\n\nfragment VideoFragmentV2 on Video {\n  ...VideoFragmentV1\n  description\n  duration(unit: MILLISECOND)\n  isLivePreview\n  isPremiumContent\n  isPremiumContentPaid\n  liveStartScheduled\n  premiumContentPrice\n  publishStatus\n  stereoscopicType\n  thumbnails {\n    jpgThumbnail720x405\n    __typename\n  }\n  feature {\n    id\n    __typename\n  }\n  trailer {\n    id\n    __typename\n  }\n  __typename\n}\n\nfragment VideoFragmentV1 on Video {\n  type\n  id\n  name\n  isLiveStream\n  author {\n    ...UserFragmentV1\n    __typename\n  }\n  __typename\n}\n\nfragment UserFragmentV1 on User {\n  type\n  id\n  name\n  thumbnails {\n    userProfileLight\n    __typename\n  }\n  __typename\n}\n\nfragment UserFragmentV4 on User {\n  ...UserFragmentV3\n  videos(representation: 0) {\n    totalCount\n    __typename\n  }\n  __typename\n}\n\nfragment UserFragmentV3 on User {\n  ...UserFragmentV2\n  description\n  thumbnails {\n    profileBg1440x420\n    __typename\n  }\n  __typename\n}\n\nfragment UserFragmentV2 on User {\n  ...UserFragmentV1\n  followersCount\n  iAmFollowing\n  __typename\n}\n\nfragment CommentFragmentV1 on Comment {\n  id\n  abuseReported\n  author {\n    ...UserFragmentV1\n    __typename\n  }\n  createdAt\n  text\n  renderedText\n  votesUp\n  votesDown\n  votedUp\n  votedDown\n  isRestricted\n  __typename\n}\n"
      })
      graphql_request({
        ["query"]="{\n          videos(ids: \"" .. item_value .. "\") {\n            \n  audioType\n  author {\n    id\n    name\n    thumbnails {\n      userProfileLight\n    }\n  }\n  categories {\n    id\n  }\n  commentCount(sla: Factual)\n  description\n  downloadableVideo {\n    resolutionHorizontal\n    resolutionVertical\n  }\n  duration(unit: SECOND)\n  errorCodeV2\n  extraDates {\n    created\n    published\n  }\n  feature {\n    id\n  }\n  hasCustomThumbnail\n  id\n  isPremiumContent\n  isPremiumContentPaid\n  isLivePreview\n  liveStartScheduled\n  liveStopScheduled\n  name\n  permission\n  premiumContentPrice\n  privateFields {\n    clientMetadata {\n      filename\n    }\n    committedEdits\n    liveIngestUrl\n    pendingPermission\n    retranscode\n    source\n    thumbnailComplete\n    transcodingDetails\n    verificationStatus\n    version\n  }\n  publishStatus\n  published\n  reaction(sla: Factual) {\n    like\n    dislike\n  }\n  stereoscopicType\n  tags {\n    name\n  }\n  thumbnails {\n    jpgThumbnail1280x720(useDefault: false)\n  }\n  trailer {\n    id\n  }\n  transcodingStatus {\n    high\n    hls\n    messageRaw\n    uploaded\n    web\n  }\n\n          }\n        }"
      })
      check("https://samsungvr.com/cdn/" .. item_value .. "/master_list.m3u8")
    end
    if string.match(url, "%.m3u8$") then
      for line in string.gmatch(html, "([^\n]+)") do
        checknewshorturl(line)
        checknewurl(line)
      end
    end
    for newurl in string.gmatch(string.gsub(html, "&quot;", '"'), '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(string.gsub(html, "&#039;", "'"), "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, "[^%-]href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, '[^%-]href="([^"]+)"') do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, ":%s*url%(([^%)]+)%)") do
      checknewurl(newurl)
    end
  end

  return urls
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]
  
  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. "  \n")
  io.stdout:flush()

  if status_code >= 300 and status_code <= 399 then
    local newloc = urlparse.absolute(url["url"], http_stat["newloc"])
    if downloaded[newloc] == true or addedtolist[newloc] == true
      or not allowed(newloc, url["url"]) then
      tries = 0
      return wget.actions.EXIT
    end
  end
  
  if status_code >= 200 and status_code <= 399 then
    downloaded[url["url"]] = true
  end

  if abortgrab == true then
    io.stdout:write("ABORTING...\n")
    io.stdout:flush()
    return wget.actions.ABORT
  end

  if status_code >= 500
    or (
      status_code >= 400
      and status_code ~= 404
    )
    or status_code == 0 then
    io.stdout:write("Server returned " .. http_stat.statcode .. " (" .. err .. "). Sleeping.\n")
    io.stdout:flush()
    local maxtries = 12
    if not allowed(url["url"], nil) then
      maxtries = 3
    end
    if tries >= maxtries then
      io.stdout:write("I give up...\n")
      io.stdout:flush()
      tries = 0
      if maxtries == 3 then
        return wget.actions.EXIT
      else
        return wget.actions.ABORT
      end
    else
      os.execute("sleep " .. math.floor(math.pow(2, tries)))
      tries = tries + 1
      return wget.actions.CONTINUE
    end
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
  if abortgrab == true then
    return wget.exits.IO_FAIL
  end
  return exit_status
end

