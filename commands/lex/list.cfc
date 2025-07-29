/**
* Shows a list of the currently installed extensions on a Lucee server
*/
component {

    property name='lexService' inject='LexService@commandbox-lex';
    property name="serverService" inject="ServerService";
    property name="fileSystemUtil" inject="FileSystem";

    /**
     * @name.hint the short name of the server
     * @name.optionsUDF serverNameComplete
     * @directory.hint web root for the server
     * @serverConfigFile The path to the server's JSON file.
     * @updatable.hint only list extensions that can be updated
     * @provider.hint provider to list extension updates from
     * @provider.optionsUDF providersComplete
     * @prerelease.hint include prerelease version updates
     **/
    function run(
        string name,
        string directory,
        string serverConfigFile,
        boolean updatable = false,
        string provider = '',
        boolean prerelease = false
    ) {
        if ( !isNull( arguments.directory ) ) {
            arguments.directory = fileSystemUtil.resolvePath( arguments.directory );
        }
        if ( !isNull( arguments.serverConfigFile ) ) {
            arguments.serverConfigFile = fileSystemUtil.resolvePath( arguments.serverConfigFile );
        }

        var serverInfo = serverService.resolveServerDetails( arguments ).serverinfo;

        if ( !lexService.isLuceeServer( serverInfo ) ) {
            print.redLine( 'Cannot find a valid Lucee server.' );
            return;
        }

        for ( var extension in lexService.getServerExtensionList( serverInfo, provider, prerelease ) ) {
            if ( updatable && extension.updateVersion.isEmpty() ) continue;
            print.whiteOnLightSeaGreenLine( '  ' & extension.name & '  ' );
            print.boldWhiteLine( 'Id: #extension.id#' );
            print.yellowLine( 'Version: #extension.version#' );
            if ( !extension.updateVersion.isEmpty() ) {
                print.green1Line( 'Update available: #extension.updateVersion.version#  (#extension.updateVersion.provider#)' );
            }
            print.line();
        }
    }

    function serverNameComplete() {
        return serverService
            .getServerNames()
            .map( ( i ) => {
                return { name : i, group : 'Server Names' };
            } );
    }

    function providersComplete() {
        return lexService.getProviders().map( ( p ) => p.name );
    }

}
