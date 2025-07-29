/**
 * Update all lucee server extensions that have an update available
 **/
component {

    property name="serverService" inject="ServerService";
    property name='lexService' inject='LexService@commandbox-lex';

    /**
     * @name.hint the short name of the server
     * @directory.hint web root for the server
     * @serverConfigFile The path to the server's JSON file.
     * @provider.hint provider to update extensions from
     * @provider.optionsUDF providersComplete
     * @prerelease.hint include prerelease version updates
     * @wait.hint Block until deploy folder is clear and extension is listed in lucee-server.xml
     * @verbose.hint Produce more verbose information about the extension installation
     **/
    function run(
        string name,
        string directory,
        string serverConfigFile,
        string provider = '',
        boolean prerelease = false,
        boolean wait = false,
        boolean verbose = false
    ) {
        if ( !isNull( arguments.directory ) ) {
            arguments.directory = fileSystemUtil.resolvePath( arguments.directory );
        }
        if ( !isNull( arguments.serverConfigFile ) ) {
            arguments.serverConfigFile = fileSystemUtil.resolvePath( arguments.serverConfigFile );
        }

        var serverDetails = serverService.resolveServerDetails( arguments );

        if ( !lexService.isLuceeServer( serverDetails.serverInfo ) ) {
            print.redLine( 'Cannot find a valid Lucee server.' );
            return;
        }

        var basePath = getCWD();
        var extensions = lexService.getServerExtensionList( serverDetails.serverInfo, provider, prerelease );
        extensions = extensions
            .filter( ( ext ) => !ext.updateVersion.isEmpty() )
            .map((ext) => {
                ext.version = ext.updateVersion.version;
                return ext;
            });

        if ( !extensions.len() ) {
            print.yellowLine( 'No out of date extensions...exiting.' );
            return;
        }

        lexService.installExtensions(
            extensions,
            serverDetails,
            basePath,
            wait,
            3,
            verbose
        );
    }

    function providersComplete() {
        return lexService.getProviders().map( ( p ) => p.name );
    }

}
