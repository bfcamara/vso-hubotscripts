# Description:
#   A way to interact with Visual Studio Online.
#
# Dependencies:
#    "node-uuid": "~1.4.1"
#    "hubot": "~2.7.5"
#    "vso-client": "~0.1.1"
#
# Configuration:
#   HUBOT_VSONLINE_ACCOUNT - The Visual Studio Online account name (Required)
#   HUBOT_VSONLINE_USERNAME - Alternate credential username (Required in trust mode)
#   HUBOT_VSONLINE_PASSWORD - Alternate credential password (Required in trust mode)
#   HUBOT_VSONLINE_APP_ID - Visual Studion Online application ID (Required in impersonate mode)
#   HUBOT_VSONLINE_APP_SECRET - Visual Studio Online application secret (Required in impersonate mode)
#   HUBOT_VSONLINE_AUTHORIZATION_CALLBACK_URL - Visual Studio Online application oauth callback (Required in impersonate mode)
#
# Commands:
#   hubot vso show room defaults - Displays room settings
#   hubot vso set room default <key> = <value> - Sets room setting <key> with value <value>
#   hubot vso show builds - Will return a list of build definitions, along with their build number.
#   hubot vso build <build number> - Triggers a build of the build number specified.
#   hubot vso create pbi|bug|feature|impediment|task <title> with description <description> - Create a Product Backlog work item with the title and descriptions specified.  This will put it in the root areapath and iteration
#   hubot vso what have i done today - This will show a list of all tasks that you have updated today
#   hubot vso show projects - Show the list of team projects
#   hubot vso who am i - Show user info as seen in Visual Studio Online user profile
#   hubot vso forget my credential - Forgets the OAuth access token 
#
# Notes:

Client = require 'vso-client'
util = require 'util'
uuid = require 'node-uuid'
{TextMessage} = require 'hubot'

#########################################
# Constants
#########################################
VSO_CONFIG_KEYS_WHITE_LIST = {
  "project":
    help: "Project not set for this room. Set with hubot vso set room default project = {project name or ID}"
}

VSO_TOKEN_CLOSE_TO_EXPIRATION_MS = 120*1000

#########################################
# Helper class to manage VSOnline brain 
# data
#########################################
class VsoData
  
  constructor: (robot) ->
  
    ensureVsoData = ()=>
      robot.logger.debug "Ensuring vso data correct structure"
      @vsoData ||= {}    
      @vsoData.rooms ||= {}
      @vsoData.authorizations ||= {}
      @vsoData.authorizations.states ||= {}
      @vsoData.authorizations.users ||= {}
      robot.brain.set 'vsonline', @vsoData 
  
    # try to read vso data from brain
    @loaded = false
    @vsoData = robot.brain.get 'vsonline'
    if not @vsoData
      ensureVsoData()
      # and now subscribe for the onload for cases where brain is loading yet
      robot.brain.on 'loaded', =>
        return if @loaded is true
        robot.logger.debug "Brain loaded. Recreate vso data with the data loaded from brain"
        @loaded = true
        @vsoData = robot.brain.get 'vsonline'
        ensureVsoData()
    else
      ensureVsoData()
      
            
  roomDefaults: (room) ->
    @vsoData.rooms[room] ||= {}
    
  getRoomDefault: (room, key) ->
    @vsoData.rooms[room]?[key]
  
  addRoomDefault: (room, key, value) ->
    @roomDefaults(room)[key] = value
  
  getOAuthTokenForUser: (userId) ->
    @vsoData.authorizations.users[userId]
    
  addOAuthTokenForUser: (userId, token) ->
    @vsoData.authorizations.users[userId] = token
  
  removeOAuthTokenForUser: (userId) ->
    delete @vsoData.authorizations.users[userId]
    
  addOAuthState: (state, stateData) ->
    @vsoData.authorizations.states[state] = stateData
  
  getOAuthState: (state) ->
    @vsoData.authorizations.states[state]
    
  removeOAuthState: (state) ->
    delete @vsoData.authorizations.states[state]


module.exports = (robot) ->
  # Required env variables
  account = process.env.HUBOT_VSONLINE_ACCOUNT
  accountCollection = process.env.HUBOT_VSONLINE_COLLECTION_NAME || "DefaultCollection"

  # Optional env variables to allow override a different environment
  environmentDomain = process.env.HUBOT_VSONLINE_ENV_DOMAIN || "visualstudio.com"
  vsoAdminRoleName = process.env.HUBOT_VSONLINE_ADMIN_ROLE_NAME || "vsoadmin"
  
  # Required env variables to run in trusted mode
  username = process.env.HUBOT_VSONLINE_USERNAME
  password = process.env.HUBOT_VSONLINE_PASSWORD

  
  # Required env variables to run with OAuth (impersonate mode)
  appId = process.env.HUBOT_VSONLINE_APP_ID
  appSecret = process.env.HUBOT_VSONLINE_APP_SECRET
  oauthCallbackUrl = process.env.HUBOT_VSONLINE_AUTHORIZATION_CALLBACK_URL
  
  # OAuth optional env variables
  vssPsBaseUrl = process.env.HUBOT_VSONLINE_BASE_VSSPS_URL or "https://app.vssps.visualstudio.com"
  authorizedScopes = process.env.HUBOT_VSONLINE_AUTHORIZED_SCOPES or "preview_api_all preview_msdn_licensing"
  
  accountBaseUrl = "https://#{account}.#{environmentDomain}"
  impersonate = if appId then true else false
  robot.logger.info "VSOnline scripts running with impersonate set to #{impersonate}"

  accountBaseUrl = "https://#{account}.visualstudio.com"
  
  if impersonate
    oauthCallbackPath = require('url').parse(oauthCallbackUrl).path
    accessTokenUrl = "#{vssPsBaseUrl}/oauth2/token"
    authorizeUrl = "#{vssPsBaseUrl}/oauth2/authorize"
  
  vsoData = new VsoData(robot)

  robot.on 'error', (err, msg) ->
    robot.logger.error "Error in robot: #{util.inspect(err)}"

  #########################################
  # OAuth helper functions
  #########################################
  needsVsoAuthorization = (msg) ->
    return false unless impersonate
    
    userToken = vsoData.getOAuthTokenForUser(msg.envelope.user.id)
    return not userToken
    
  buildVsoAuthorizationUrl = (state)->
    "#{authorizeUrl}?\
      client_id=#{appId}\
      &response_type=Assertion&state=#{state}\
      &scope=#{escape(authorizedScopes)}\
      &redirect_uri=#{escape(oauthCallbackUrl)}"
      
  askForVsoAuthorization = (msg) ->
    state = uuid.v1().toString()
    vsoData.addOAuthState state,
      createdAt: new Date
      envelope: msg.envelope
    vsoAuthorizeUrl = buildVsoAuthorizationUrl state
    return msg.reply "I don't know who you are in Visual Studio Online.
      Click the link to authenticate #{vsoAuthorizeUrl}"
      
  getVsoOAuthAccessToken = ({user, assertion, refresh, success, error}) ->
    tokenOperation = if refresh then Client.refreshToken else Client.getToken
    tokenOperation appSecret, assertion, oauthCallbackUrl, (err, res) ->
      unless err or res.Error? 
        token = res
        expires_at = new Date
        expires_at.setTime(
          expires_at.getTime() + parseInt(token.expires_in, 10)*1000)

        token.expires_at = expires_at
        vsoData.addOAuthTokenForUser(user.id, token)
        success(err, res) if typeof success is "function"
      else
        robot.logger.error "Error getting VSO oauth token: #{util.inspect(err or res.Error)}"
        error(err, res) if typeof error is "function"
        
  accessTokenExpired = (user) ->
    token = vsoData.getOAuthTokenForUser(user.id)
    expiresAt = new Date token.expires_at
    now = new Date
    return (expiresAt - now) < VSO_TOKEN_CLOSE_TO_EXPIRATION_MS        

  #########################################
  # VSOnline helper functions
  #########################################
  assertUserIsVsoAdmin = (msg) ->
    return true if robot.auth.hasRole(msg.envelope.user, vsoAdminRoleName)
    
    msg.reply "Permission denied. Sorry, you're not a VSO admin role."
    return false
  
  createVsoClient = ({url, collection, user}) ->
    url ||= accountBaseUrl
    collection ||= accountCollection
    
    if impersonate
      token = vsoData.getOAuthTokenForUser user.id
      Client.createOAuthClient url, collection, token.access_token
    else
      Client.createClient url, collection, username, password
  
  runVsoCmd = (msg, {url, collection, cmd}) ->
    return askForVsoAuthorization(msg) if needsVsoAuthorization(msg)
    
    user = msg.envelope.user
    
    vsoCmd = () ->
      url ||= accountBaseUrl
      collection ||= accountCollection
      client = createVsoClient url: url, collection: collection, user: user
      cmd(client)
    
    if impersonate and accessTokenExpired(user)
      robot.logger.info "VSO token expired for user #{user.id}. Let's refresh"
      token = vsoData.getOAuthTokenForUser(user.id)
      getVsoOAuthAccessToken 
        user: user
        assertion: token.refresh_token
        refresh: true
        success: vsoCmd
        error: (err, res) ->
          msg.reply "Your VSO oauth token has expired and there\
            was an error refreshing the token.
            Error: #{util.inspect(err or res.Error)}"
    else
      vsoCmd()
      
  handleVsoError = (msg, err) ->
    msg.reply "Error executing command: #{util.inspect(err)}" if err
    
  #########################################
  # Room defaults helper functions
  #########################################
  checkRoomDefault = (msg, key) ->
    val = vsoData.getRoomDefault msg.envelope.room, key
    unless val
      help = VSO_CONFIG_KEYS_WHITE_LIST[key]?.help or
        "Error: room default '#{key}' not set."
      msg.reply help
      
    return val    

  #########################################
  # OAuth call back endpoint
  #########################################
  if impersonate then robot.router.get oauthCallbackPath, (req, res) ->
    
    # check state argument
    state = req?.query?.state
    return res.send(400, "Invalid state") unless state and stateData = vsoData.getOAuthState(state)

    # check code argument
    code = req?.query?.code
    return res.send(400, "Missing code parameter") unless code

    getVsoOAuthAccessToken
      user: stateData.envelope.user,
      assertion: code,
      refresh: false,
      success: -> 
        res.send """
          <html>
            <body>
            <p>Great! You've authorized Hubot to perform tasks on your behalf.
            <p>You can now close this window.</p>
            </body>
          </html>"""            
        vsoData.removeOAuthState state
        robot.receive new TextMessage stateData.envelope.user, stateData.envelope.message.text
      error: (err, res) ->
        res.send """
          <html>
            <body>
            <p>Ooops! It wasn't possible to get an OAuth access token for you.</p>
            <p>Error returned from VSO: #{util.inspect(err or res.Error)}</p>
            </body>
          </html>"""
          
  #########################################
  # Profile related commands
  #########################################
  robot.respond /vso who am i(\?)*/i, (msg) ->
    unless impersonate
      return msg.reply "It's not possible to know who you are since I'm running \
      with no impersonate mode."

    runVsoCmd msg, url: vssPsBaseUrl, collection: "/", cmd: (client) ->
      client.getCurrentProfile (err, res) ->
        return handleVsoError msg, err if err
        msg.reply "You're #{res.displayName} \
          and your email is #{res.emailAddress}"           

  robot.respond /vso forget my credential/i, (msg) ->
    unless impersonate
      return msg.reply "I'm not running in impersonate mode, \
      which means I don't have your credentials."
    
    vsoData.removeOAuthTokenForUser msg.envelope.user.id
    msg.reply "Done! In the next VSO command you'll need to dance OAuth again"

  #########################################
  # Room defaults related commands
  #########################################
  robot.respond /vso show room defaults/i, (msg)->
    defaults = vsoData.roomDefaults msg.envelope.room
    reply = "VSOnline defaults for this room:\n"
    reply += "#{key}: #{defaults?[key] or '<Not set>'} \n" for key of VSO_CONFIG_KEYS_WHITE_LIST
    msg.reply reply
    
  robot.respond /vso set room default ([\w]+)\s*=\s*(.*)\s*$/i, (msg) ->
    return unless assertUserIsVsoAdmin msg
    return msg.reply "Unknown setting #{msg.match[1]}" unless msg.match[1] of VSO_CONFIG_KEYS_WHITE_LIST
    
    vsoData.addRoomDefault(msg.envelope.room, msg.match[1], msg.match[2])
    msg.reply "Room default for #{msg.match[1]} set to #{msg.match[2]}"
    
  robot.respond /vso show projects/i, (msg) ->
    runVsoCmd msg, cmd: (client) ->
      client.getProjects (err, projects) ->
        return handleVsoError msg, err if err
        reply = "VSOnline projects for account #{account}: \n"
        reply += p.name + "\n" for p in projects
        msg.reply reply

  #########################################
  # Build related commands
  #########################################
  robot.respond /vso show builds/i, (msg) ->
    runVsoCmd msg, cmd: (client) ->
      definitions=[]
      client.getBuildDefinitions (err, buildDefinitions) ->
        return handleVsoError msg, err if err
        
        definitions.push "Here are the current build definitions: "
        for build in buildDefinitions
          definitions.push build.name + ' ' + build.id
        msg.reply definitions.join "\n"

  robot.respond /vso build (.*)/i, (msg) ->
    buildId = msg.match[1]
    runVsoCmd msg, cmd: (client) ->
      buildRequest =
        definition:
          id: buildId
        reason: 'Manual'
        priority : 'Normal'

      client.queueBuild buildRequest, (err, buildResponse) ->
        return handleVsoError msg, err if err
        msg.reply "Build queued.  Hope you you don't break the build! " + buildResponse.url

  #########################################
  # WIT related commands
  #########################################
  robot.respond /vso Create (PBI|Task|Feature|Impediment|Bug) (.*) (with description)? (.*)?/i, (msg) ->
    return unless project = checkRoomDefault msg, "project"
	
    addField = (wi, wi_refName, val) ->
      workItemField=
        field: 
          refName : wi_refName
        value : val
      wi.fields.push workItemField

    runVsoCmd msg, cmd: (client) ->
      title = msg.match[2]
      description = msg.match[4]
      workItem=
        fields : []
		
      addField workItem, "System.Title", title          
      addField workItem, "System.AreaPath", project
      addField workItem, "System.IterationPath", project
      addField workItem, "System.Description", description
		
      switch msg.match[1]      
        when "pbi"
          addField workItem, "System.WorkItemType", "Product Backlog Item"
          addField workItem, "System.State", "New"
          addField workItem, "System.Reason", "New Backlog Item"
        when "task"
          addField workItem, "System.WorkItemType", "Task"
          addField workItem, "System.State", "To Do"
          addField workItem, "System.Reason", "New Task"
        when "feature"
          addField workItem, "System.WorkItemType", "Feature"
          addField workItem, "System.State", "New"
          addField workItem, "System.Reason", "New Feature"
          addField workItem, "Microsoft.VSTS.Common.Priority","2"
        when "impediment"
          addField workItem, "System.WorkItemType", "Impediment"
          addField workItem, "System.State", "Open"
          addField workItem, "System.Reason", "New Impediment"
          addField workItem, "Microsoft.VSTS.Common.Priority","2"
        when "bug"
          addField workItem, "System.WorkItemType", "Bug"
          addField workItem, "System.State", "New"
          addField workItem, "System.Reason", "New Defect Reported"          

		  
      client.createWorkItem workItem, (err, createdWorkItem) ->        
        return handleVsoError msg, err if err
        msg.reply msg.match[1] + " " + createdWorkItem.id + " created.  " + createdWorkItem.webUrl		     
    
  robot.respond /vso What have I done today/i, (msg) ->
    return unless project = checkRoomDefault msg, "project"
  
    runVsoCmd msg, cmd: (client) ->
    
      #TODO - we need to change to get the user profile from VSO
      myuser = msg.message.user.displayName

      wiql="\
        select [System.Id], [System.WorkItemType], [System.Title], [System.AssignedTo], [System.State], \
        [System.Tags] from WorkItems where [System.WorkItemType] = 'Task' and [System.ChangedBy] = @me \
        and [System.ChangedDate] = @today"
    
      #console.log wiql

      client.getRepositories null, (err,repositories) ->
        return handleVsoError msg, err if err
        mypushes=[]
        today = yesterdayDate()
        for repo in repositories
          client.getCommits repo.id, null, myuser, null,today,(err,pushes) ->
            return handleVsoError msg, err if err
            numPushes = Object.keys(pushes).length
            if numPushes > 0
              mypushes.push "You have written code! These are your commits for the " + repo.name + " repo"
              for push in pushes
                mypushes.push "commit" + push.commitId
              msg.reply mypushes.join "\n"
              
      tasks=[]
      client.getWorkItemIds wiql, project, (err, ids) ->
        return handleVsoError msg, err if err
        numTasks = Object.keys(ids).length
        if numTasks >0
          workItemIds=[]
          workItemIds.push id for id in ids
         
          client.getWorkItemsById workItemIds, null, null, null, (err, items) ->
            return handleVsoError msg, err if err
            if items and items.length > 0
              tasks.push "You have worked on the following tasks today: "        
           
              for task in items
                for item in task.fields
                  if item.field.name == "Title"
                    tasks.push item.value
                    msg.reply tasks.join "\n"
        else
          msg.reply "You haven't worked on any task today"



yesterdayDate = () ->
  date = new Date()
  date.setDate(date.getDate() - 1)
  date.setUTCHours(0,0,0,0)
  date.toISOString()
