# commandbox-lex

This is a WIP CommandBox module that can list and install Lucee server extensions for you.

This module will register the `lex` namespace in CommandBox.

## Commands
```
lex show
```
Lists all Lucee extensions currently available from Lucee extension providers. (At this time that means Lucee and ForgeBox.)

```
lex list
```
Lists all Lucee server extensions installed on the server present in the CWD.

*Note:* One can also specify a server name, or a path to a server webroot, or server config file (server.json). These commands will all try to follow the same server resolution strategy as the `server` commands in the CommandBox core.

```
lex install id@version
lex install ./path/to/extension.lex
lex install https://site.com/path/to/extension.lex
lex install s3://bucket/path/to/extension.lex
```
In each case, the command first resolves the extension location to a local file path, then copies that file into the Lucee server's deploy directory. The `--wait` flag can be specified in order to have the command block until the deploy folder has emptied and the extension is contained in the `lucee-server.xml` file:
```
lex install id@version --wait
```
After installation, information about the extension is written to the `server.json` file in an array under the key `"luceeServerExtensions"`. Each entry has the following format:
```
{
    "id":"99A4EF8D-F2FD-40C8-8FB8C2E67A4EEEB6",
    "version":"6.2.2.jre8",
    "name":"Microsoft SQL Server (Vendor Microsoft)",
    "location":"http://extension.lucee.org/rest/extension/provider/full/99A4EF8D-F2FD-40C8-8FB8C2E67A4EEEB6?version=6.2.2.jre8"
}
```
Note that the location will vary based on where the extension was installed from:
```
{
    "id":"99A4EF8D-F2FD-40C8-8FB8C2E67A4EEEB6",
    "version":"6.2.2.jre8",
    "name":"Microsoft SQL Server (Vendor Microsoft)",
    "location":"s3://my-bucket/extensions/mssql-6.2.2.lex"
}
```
If  `lex install` is run without providing an extension to install, the command will read all the extensions defined in your `server.json` file and attempt to install them if they are not currently installed on the server.

```
lex update
lex update --prerelease
```
Downloads and installs any extension updates that are available from extension providers for extensions currently installed on your server. Specifying the `--prerelease` flag will allow prerelease version updates to be installed.
