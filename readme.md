## Hubot scripts for Visual Studio Online

A collection of Hubot scripts to perform tasks in Visual Studio Online.

### Introduction

Hubot scripts for Visual Studio Online provides many commands to perform
tasks in Visual Studio Online.

The scripts can run in two modes

+ Trusted mode: the tasks against Visual Studio Online are performed using 
  the same account
+ Impersonate mode: the tasks against Visual Studio Online are perfomed on 
  behalf of the user issuing the command. In this mode the user has to explicitly 
  authorize hubot

### Installation

To install, in your Hubot instance directory

```
npm install hubot-vso-scripts
```


Include the package in your hubot's external-scripts.json

```
["hubot-vso-scripts"]
```

### Configuration

The required environment variables are

+ **HUBOT\_VSONLINE\_ACCOUNT** - The Visual Studio Online account's name

*Trust Mode*

In trust mode we need to set the alternate credentials of the user who  will perform the tasks

+ **HUBOT\_VSONLINE\_USERNAME**: The alternate credentials username
+ **HUBOT\_VSONLINE\_PASSWORD**: The alternate credentials password

We can use a service account instead of a real user by setting the variable **HUBOT\_VSONLINE\_USER\_IS_SERVICE\_ACCOUNT** to `true`.
In this case, the credentials set shouldn't be the alternate credentials.
To get a Visual Studio Online service account you can use the [TFS Service Credential Viewer](http://nakedalm.com/getting-service-account-vso-tfs-service-credential-viewer/)


*Impersonate Mode*

In impersonate we need to set the variables defined in the application registered in Visual Studio Online
(Click [here](http://www.visualstudio.com/integrate/get-started-auth-oauth2-vsi) to know how to register an 
application in Visual Studio Online

+ **HUBOT\_VSONLINE\_APP\_ID**: The application ID
+ **HUBOT\_VSONLINE\_APP\_SECRET**: The application secret
+ **HUBOT\_VSONLINE\_AUTHORIZATION\_CALLBACK\_URL**: The OAuth callback URL. This URL must be available from 
  the chat service you're using


### License

MIT


