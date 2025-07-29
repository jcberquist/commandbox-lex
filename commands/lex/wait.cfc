/**
 * Wait for a Lucee extensions to install by id or via the server json
 **/
component {

    property name="serverService" inject="ServerService";
    property name='lexService' inject='LexService@commandbox-lex';

    /**
     * @extension.hint the ID of the extension to install
     * @extension.optionsUDF extensionComplete
     * @name.hint the short name of the server
     * @directory.hint web root for the server
     * @serverConfigFile The path to the server's JSON file.
     * @wait.hint Block until deploy folder is clear and extension is listed in lucee-server.xml
     * @verbose.hint Produce more verbose information about the extension installation
     **/
    function run(
        string extension = '',
        string name,
        string directory,
        string serverConfigFile,
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
        var extensions = listToArray( extension );

        if ( !extensions.len() ) {
            // no extension passed via CLI so look to server.json
            extensions = serverDetails.serverJSON.luceeServerExtensions ?: [ ];
            basePath = serverDetails.serverInfo.serverConfigFile;
        }

        lexService.waitForExtensions(
            extensions,
            serverDetails,
            basePath,
            3,
            verbose
        );
    }

    function extensionComplete( string paramSoFar ) {
        var extensions = lexService.getProviderExtensions();
        var id = paramSoFar.listFirst( '@' );
        if ( extensions.keyExists( id ) ) {
            return extensions[ id ].versions.keyArray().map( ( v ) => id & '@' & v );
        }

        return extensions.reduce( ( comps, id, info ) => {
            comps.append( { name: id, group: 'Extensions', description: info.name } );
            return comps;
        }, [ ] );
    }

}
