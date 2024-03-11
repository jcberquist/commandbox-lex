component accessors="true" {

    property name="configService" inject="ConfigService";
    property name="CR" inject="CR@constants";
    property name="fileSystemUtil" inject="FileSystem";
    property name="ProgressableDownloader" inject="ProgressableDownloader";
    property name="progressBar" inject="progressBar";
    property name="s3Service" inject="S3Service";
    property name="serverService" inject="ServerService";
    property name="shell" inject="Shell";
    property name="tempDir" inject="tempDir@constants";
    property name='job' inject='InteractiveJob';
    property name='JSONService' inject='JSONService';

    property name="providers" type="array";
    property name="providerExtensions" type="struct";

    function init() {
        setProviders( [
            {
                name: 'ForgeBox',
                download: 'https://www.forgebox.io',
                info: [ 'https://www.forgebox.io' ] },
            {
                name: 'Lucee',
                download: 'http://extension.lucee.org',
                info: [ 'http://extension.lucee.org', 'http://beta.lucee.org' ]
            }
        ] );
    }

    function isLuceeServer( struct serverInfo ) {
        if ( !serverInfo.engineName.startsWith( 'lucee' ) ) return false;
        if ( serverInfo.engineVersion.left( 1 ) != '5' ) return false;
        var configFile = serverInfo.serverHomeDirectory & serverInfo.serverConfigDir & '/lucee-server/context/lucee-server.xml';
        return fileExists( configFile );
    }

    function getServerExtensions( struct serverInfo, string provider = '', boolean prerelease = false ) {
        var providerExtensions = getProviderExtensions();
        var configFile = serverInfo.serverHomeDirectory & serverInfo.serverConfigDir & '/lucee-server/context/lucee-server.xml';
        var serverConfig = xmlParse( fileRead( configFile ) );
        var extensionsSource = xmlSearch( serverConfig, '/cfLuceeConfiguration/extensions' );
        var extensions = { };
        if ( extensionsSource.len() ) {
            for ( var extensionXML in extensionsSource[ 1 ].XMLChildren ) {
                var extension = { };
                extension.append( extensionXML.XMLAttributes );
                extensions[ extension.id ] = {
                    name: extension.name,
                    version: extension.version,
                    filename: extension[ 'file-name' ],
                    updateVersion: { }
                };
                if ( providerExtensions.keyExists( extension.id ) ) {
                    var lv = latestVersion( providerExtensions[ extension.id ].versions, provider, prerelease );
                    if ( !lv.isEmpty() && versionSort( extension.version, lv.version ) == 1 ) {
                        extensions[ extension.id ].updateVersion = lv;
                    }
                }
            }
        }
        return extensions;
    }

    function getServerExtensionList( struct serverInfo, string provider = '', boolean prerelease = false ) {
        var extensions = getServerExtensions( serverInfo, provider, prerelease );
        var extList = [ ];
        for ( var id in extensions ) {
            extList.append( {
                id: id,
                name: extensions[ id ].name,
                version: extensions[ id ].version,
                updateVersion: extensions[ id ].updateVersion
            } );
        }

        extList.sort( ( a, b ) => compare( a.name.lcase(), b.name.lcase() ) );

        return extList;
    }

    function getProviderExtensions() {
        if ( isNull( providerExtensions ) ) {
            providerExtensions = { };
            for ( var providerData in providers ) {
                for ( var source in providerData.info ) {
                    var req = makeHTTPRequest( source & '/rest/extension/provider/info?type=all' );
                    var resData = deserializeJSON( req.filecontent );
                    resData.extensions.data.each( ( row ) => {
                        var extension = row.reduce( ( ext, column, i ) => {
                            ext[ resData.extensions.columns[ i ] ] = column;
                            return ext;
                        }, { } );
                        if ( !providerExtensions.keyExists( extension.id ) ) {
                            providerExtensions[ extension.id ] = { name: extension.name, versions: { } };
                        }
                        var versions = [ extension.version ];
                        versions.append( extension.older, true );
                        for ( var version in versions ) {
                            if ( !providerExtensions[ extension.id ].versions.keyExists( version ) ) {
                                providerExtensions[ extension.id ].versions[ version ] = { provider: providerData.name, source: source };
                            }
                        }
                    } );
                }
            }
        }

        return providerExtensions;
    }

    function getProviderExtensionList( string filter = '', string provider = '', boolean prerelease = false ) {
        var extList = [ ];
        var extensionStruct = getProviderExtensions( provider );
        for ( var id in extensionStruct ) {
            var ext = { id: id, name: extensionStruct[ id ].name };
            ext.latestVersion = latestVersion( extensionStruct[ id ].versions, provider, prerelease );
            if (
                !ext.latestVersion.isEmpty() &&
                ( !filter.len() || ext.name.findNoCase( filter ) )
            ) {
                extList.append( ext );
            }
        }

        extList.sort( ( a, b ) => compare( a.name.lcase(), b.name.lcase() ) );

        return extList;
    }

    function installExtensions(
        array extensions,
        struct serverDetails,
        string basePath,
        boolean waitForDeploy = true,
        numeric minutes = 3,
        boolean verbose = false
    ) {
        job.start( 'Lucee extension installer.' );

        var installed = [ ];
        for ( var extension in extensions ) {
            var extensionInfo = installExtension( extension, serverDetails, basePath, verbose );
            if ( !isNull( extensionInfo ) ) {
                installed.append( extensionInfo );
            }
        }

        if ( waitForDeploy ) {
            waitForExtensions(
                installed,
                serverDetails,
                basePath,
                minutes
            );
        }

        updateServerJSON( serverDetails, installed );

        job.complete( verbose );
    }

    function waitForExtensions(
        array extensions,
        struct serverDetails,
        string basePath,
        numeric minutes = 3,
        boolean verbose = false
    ) {
        job.start( 'Waiting for extensions to deploy.' );

        if ( !serverService.isServerRunning( serverDetails.serverInfo ) ) {
            job.error( 'Server is not currently running...extensions will not be picked up until it is next started.', verbose );
            return;
        }

        var startTick = getTickCount();
        var deployDir = serverDetails.serverInfo.serverHomeDirectory & serverDetails.serverInfo.serverConfigDir & '/lucee-server/deploy/';
        var extensionsToDeploy = directoryList( deployDir, false, 'path' );
        var extensionsToWaitFor = extensions
            .map( ( ext ) => {
                return resolveExtensionInfo( ext, basePath, serverDetails.serverInfo.serverConfigFile );
            } )
            .filter( ( extInfo ) => {
                var canWait = extInfo.id.len() && extInfo.version.len();
                if ( !canWait ) {
                    job.addWarnLog( 'Skipping extension as it is missing id and or version.' );
                }
                return canWait;
            } );

        while ( extensionsToDeploy.len() || extensionsToWaitFor.len() ) {
            if ( extensionsToDeploy.len() ) {
                extensionsToDeploy = directoryList( deployDir, false, 'path' );
                if ( !extensionsToDeploy.len() ) {
                    job.addLog( 'Deploy folder cleared.' );
                }
            } else if ( extensionsToWaitFor.len() ) {
                var updatedExtensions = getServerExtensions( serverDetails.serverInfo );
                extensionsToWaitFor = extensionsToWaitFor.filter( ( extInfo ) => {
                    return (
                        !updatedExtensions.keyExists( extInfo.id ) ||
                        !updatedExtensions[ extInfo.id ].version == extInfo.version
                    );
                } );
                if ( !extensionsToWaitFor.len() ) {
                    job.addLog( 'Extension(s) are present in lucee-server.xml config.' );
                }
            }

            // check for interrupt
            shell.checkInterrupted();

            // don't wait forever
            if ( getTickCount() - startTick > minutes * 60000 ) {
                job.error( 'Waited for #minutes# minute(s)...aborting.', verbose );
                return;
            }

            sleep( 1000 );
        }

        job.complete( verbose );
    }

    private function installExtension( any extension, struct serverDetails, string basePath ) {
        job.start( 'Installing #extensionName( extension )#' );
        var currentExtensions = getServerExtensions( serverDetails.serverInfo );
        var extensionInfo = resolveExtensionInfo( extension, basePath, serverDetails.serverInfo.serverConfigFile );

        // if we have a defined id and version, check current extensions
        // to see if install is necessary
        var extName = installedExtensionName( extensionInfo, currentExtensions );
        if ( extName.len() ) {
            extensionInfo.name = extName;
            job.addWarnLog( extensionName( extensionInfo ) & ' has already been installed.' )
            job.complete();
            return extensionInfo;
        }

        // at this point check that we have a location
        // as we cannot proceed without one
        if ( !extensionInfo.location.len() ) {
            job.error( 'Cannot determine a location for #extensionName( extensionInfo )#.' );
            return;
        }

        var extensionPath = extensionInfo.location;

        // check for s3 path and convert to https
        if ( extensionPath.listFirst( ':' ) == 's3' ) {
            extensionPath = s3Service.generateSignedUrl( extensionPath );
        }

        // if we have an http(s) url, dowload
        if ( extensionPath.startsWith( 'http://' ) || extensionPath.startsWith( 'https://' ) ) {
            job.addLog( 'Downloading: ' & extensionPath );
            extensionPath = downloadExtension( extensionPath );
        }

        // resolve file path
        var pathIsAbsolute = reFindNoCase( '^(\\\\|/|[a-z]:/)', fileSystemUtil.normalizeSlashes( extensionPath ) );
        extensionPath = fileSystemUtil.resolvePath( extensionPath, basePath );
        job.addLog( 'Local path: ' & extensionPath );

        // if path was relative, make it relative to server.json for tracking, if possible
        if ( !pathIsAbsolute ) {
            extensionInfo.location = makeRelativePath( extensionPath, serverDetails.serverInfo.serverConfigFile );
            job.addLog( extensionPath );
            job.addLog( serverDetails.serverInfo.serverConfigFile );
            job.addLog( extensionInfo.location );
        }

        // load metadata
        extensionInfo.append( getExtensionMetadata( extensionPath ) );

        job.addLog( 'Deploying: #extensionName( extensionInfo )#' );
        var deployDir = serverDetails.serverInfo.serverHomeDirectory & serverDetails.serverInfo.serverConfigDir & '/lucee-server/deploy/';
        job.addLog( deployDir );
        directoryCreate( deployDir, true, true );
        fileCopy( extensionPath, deployDir & getFileFromPath( extensionPath ) );

        job.complete();
        return extensionInfo;
    }

    private function installedExtensionName( struct extensionInfo, struct currentExtensions ) {
        if ( !extensionInfo.id.len() || !extensionInfo.version.len() ) {
            return '';
        }
        if (
            !currentExtensions.keyExists( extensionInfo.id ) ||
            !currentExtensions[ extensionInfo.id ].version == extensionInfo.version
        ) {
            return '';
        }

        return currentExtensions[ extensionInfo.id ].name;
    }

    private function extensionName( any extension ) {
        if ( isSimpleValue( extension ) ) {
            return extension;
        }
        var fullName = extension.name;
        if ( extension.id.len() ) {
            if ( fullName.len() ) fullName &= ' ';
            fullName &= extension.id;
            if ( extension.version.len() ) {
                fullName &= '@' & extension.version;
            }
        }
        return fullName;
    }

    private function latestVersion( struct versions, string provider = '', boolean prerelease = false ) {
        var versionsIds = versions.keyArray().sort( versionSort );
        for ( var version in versionsIds ) {
            var versionInfo = { version: version };
            versionInfo.append( versions[ version ] );
            if ( provider.len() && provider != versionInfo.provider ) {
                continue;
            }
            if ( !prerelease && version.listLen( '-' ) > 1 ) {
                continue;
            }
            return versionInfo;
        }
        return { };
    }

    private function resolveExtensionInfo( any extension, string basePath, string serverConfigFile ) {
        if ( isSimpleValue( extension ) ) {
            var extensionInfo = resolveExtensionString( extension, basePath, serverConfigFile );
        } else {
            var extensionInfo = {
                'id': extension.id ?: '',
                'location': extension.location ?: '',
                'name': extension.name ?: '',
                'version': extension.version ?: ''
            };
        }

        // if we were passed a struct without a location, check for id and version
        // we might be able to get a location from those
        if ( isStruct( extension ) && !extensionInfo.location.len() ) {
            if ( extensionInfo.id.len() ) {
                var extensionString = extensionInfo.id;
                if ( extensionInfo.version.len() ) {
                    extensionString &= '@' & extensionInfo.version;
                }
                extensionInfo.location = resolveExtensionString( extensionString, basePath, serverConfigFile ).location;
            }
        }

        return extensionInfo;
    }

    private function resolveExtensionString( string extension, string basePath, string serverConfigFile ) {
        // extension could be a location
        var extensionInfo = {
            'id': '',
            'location': extension,
            'name': '',
            'version': ''
        };

        // is extension a file path
        var pathIsAbsolute = reFindNoCase( '^(\\\\|/|[a-z]:/)', fileSystemUtil.normalizeSlashes( extensionInfo.location ) );
        var extensionPath = fileSystemUtil.resolvePath( extensionInfo.location, basePath );
        if ( fileExists( extensionPath ) ) {
            // we can fill out the details by reading the manifest
            extensionInfo.append( getExtensionMetadata( extensionPath ) );

            // if extension path is relative, make it relative to server.json
            if ( !pathIsAbsolute ) {
                extensionInfo.location = makeRelativePath( extensionPath, serverConfigFile );
            }
            return extensionInfo;
        }

        // could be a remote path
        if ( [ 'http', 'https', 's3' ].findNoCase( extension.listFirst( ':' ) ) ) {
            return extensionInfo;
        }

        // at this point the assumption is we were passed an id@version
        extensionInfo.id = extension.listFirst( '@' );
        extensionInfo.version = extension.listRest( '@' );
        extensionInfo.location = '';

        // abort early if not available from a provider
        if ( !getProviderExtensions().keyExists( extensionInfo.id ) ) {
            return extensionInfo;
        }

        // this extension is available from a provider
        // verify version and add name and location
        job.addLog( 'Extension is available via provider.' )
        var ext = getProviderExtensions()[ extensionInfo.id ];
        var provider = '';

        // we can assign the name field
        extensionInfo.name = ext.name;

        // validate extension version
        if ( extensionInfo.version.len() ) {
            if ( ext.versions.keyExists( extensionInfo.version ) ) {
                provider = ext.versions[ extensionInfo.version ].provider;
            } else {
                job.addErrorLog( 'Invalid extension version.' );
            }
        } else {
            // no version provided
            // see if we can find a stable version via a provider
            job.addWarnLog( 'No version provided, searching for latest stable version.' );
            var lv = latestVersion( ext.versions );
            if ( !lv.isEmpty() ) {
                extensionInfo.version = lv.version;
                provider = lv.provider;
                job.addSuccessLog( 'Found version #extensionInfo.version#' )
            }
            if ( !extensionInfo.version.len() ) {
                // no available stable version
                job.addWarnLog( 'Unable to find stable version.' );
            }
        }

        // if we were able to find a provider
        // we can now add a location
        for ( var providerInfo in getProviders() ) {
            if ( providerInfo.name == provider ) {
                var extRoute = '/rest/extension/provider/full/' & extensionInfo.id & '?version=' & extensionInfo.version;
                extensionInfo.location = providerInfo.download & extRoute;
            }
        }

        return extensionInfo;
    }

    private function updateServerJSON( serverDetails, extensions ) {
        if ( !serverDetails.serverJSON.keyExists( 'luceeServerExtensions' ) ) {
            serverDetails.serverJSON[ 'luceeServerExtensions' ] = [ ];
        }

        var extMap = serverDetails.serverJSON.luceeServerExtensions.filter( ( ext ) => {
            return ext.keyExists( 'id' ) && ext.id.len() && ext.keyExists( 'version' ) && ext.version.len();
        } )
            .reduce( ( extMap, ext ) => {
            extMap[ ext.id ] = ext;
            return extMap;
        }, { } );

        for ( var extInfo in extensions ) {
            extMap[ extInfo.id ] = extInfo;
        }

        var extList = extMap.keyArray().map( ( id ) => extMap[ id ] );
        extList.sort( ( a, b ) => compare( a.name.lcase(), b.name.lcase() ) );

        serverDetails.serverJSON.luceeServerExtensions = extList;
        JSONService.writeJSONFile( serverDetails.serverInfo.serverConfigFile, serverDetails.serverJSON );
    }

    private function getExtensionMetadata( string extensionPath ) {
        var metadata = manifestRead( extensionPath ).main;
        return { 'id': metadata.id, 'name': metadata.name, 'version': metadata.version };
    }

    private function downloadExtension( string uri ) {
        var fileName = 'temp#randRange( 1, 1000 )#.lex';
        var fullPath = tempDir & '/' & fileName;

        try {
            // Download File
            var result = progressableDownloader.download(
                uri,
                fullPath,
                function( status ) {
                    progressBar.update( argumentCollection = status );
                },
                function( newURL ) {
                    job.addLog( 'Redirecting to: ''#arguments.newURL#''...' );
                }
            );
        } catch ( UserInterruptException var e ) {
            rethrow;
        } catch ( Any var e ) {
            throw( '#e.message##CR##e.detail#', 'extensionException' );
        };

        return fullPath;
    }

    private function versionSort( a, b ) {
        var aParsed = versionParse( a );
        var bParsed = versionParse( b );
        var partsOrder = [ 'major', 'minor', 'patch', 'build' ];
        for ( var part in partsOrder ) {
            var aPart = aParsed[ part ];
            var bPart = bParsed[ part ];
            if ( isNumeric( aPart ) && isNumeric( bPart ) ) {
                var lenDiff = aPart.len() - bPart.len();
                if ( lenDiff > 0 ) {
                    bPart = repeatString( '0', lenDiff ) & bPart;
                } else if ( lenDiff < 0 ) {
                    aPart = repeatString( '0', abs( lenDiff ) ) & aPart;
                }
            }
            if ( compare( bPart, aPart ) != 0 ) {
                return compare( bPart, aPart );
            }
        }
        return 0;
    }

    private function versionParse( string version ) {
        var parsedVersion = {
            major: '',
            minor: '',
            patch: '',
            build: '',
            prerelease: ''
        };

        var partsOrder = [ 'major', 'minor', 'patch', 'build' ];
        var partsArray = version.listFirst( '-' ).listToArray( '.' );
        for ( var i = 1; i <= partsArray.len(); i++ ) {
            parsedVersion[ partsOrder[ i ] ] = partsArray[ i ];
        }
        parsedVersion.prerelease = version.listRest( '-' );
        return parsedVersion;
    }

    function makeRelativePath( srcPath, targetPath ) {
        var count = 0;
        var srcDir = fileSystemUtil.normalizeSlashes( getDirectoryFromPath( srcPath ) ).replace( '//', '/', 'all' );
        var targetDir = fileSystemUtil.normalizeSlashes( getDirectoryFromPath( targetPath ) ).replace( '//', '/', 'all' );
        while ( true ) {
            if ( !srcDir.startsWith( targetDir ) ) {
                var pathSegment = reFindNoCase( '[^/]+/$', targetDir );
                if ( pathSegment ) {
                    count++;
                    targetDir = targetDir.mid( 1, pathSegment - 1 );
                } else {
                    return srcPath;
                }
            } else {
                var root = count ? repeatString( '../', count ) : './';
                return root & srcDir.replace( targetDir, '' ) & getFileFromPath( srcPath );
                break;
            }
        }
    }

    private function makeHTTPRequest(
        urlPath,
        method = 'GET',
        redirect = true,
        timeout = 20,
        headers = { },
        allowProxy = true
    ) {
        var req = '';
        var attributeCol = {
            url: urlPath,
            method: method,
            timeout: timeout,
            redirect: redirect,
            result: 'req'
        };

        if ( allowProxy ) {
            var proxy = configService.getSetting( 'proxy', { } );
            if ( proxy.keyExists( 'server' ) && len( proxy.server ) ) {
                attributeCol.proxyServer = proxy.server;
                for ( var key in [ 'port', 'user', 'password' ] ) {
                    if ( proxy.keyExists( key ) && len( proxy[ key ] ) ) {
                        attributeCol[ 'proxy#key#' ] = proxy[ key ];
                    }
                }
            }
        }

        cfhttp(attributeCollection = attributeCol) {
            for ( var key in headers ) {
                cfhttpparam(type='header', name=key, value=headers[ key ]);
            }
        }

        return req;
    }
}
