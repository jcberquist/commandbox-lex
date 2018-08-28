/**
* Shows a list of extensions available from the configured extension providers
*/
component {

    property name='lexService' inject='LexService@commandbox-lex';

    /**
     * @provider.hint provider to list extensions from
     * @provider.optionsUDF providersComplete
     * @prerelease.hint include prerelease versions
     **/
    function run( string provider = '', boolean prerelease = false ) {
        for ( var extension in lexService.getProviderExtensionList( provider, prerelease ) ) {
            print.whiteOnLightSeaGreenLine( '  ' & extension.name & '  ' );
            print.boldWhiteLine( 'ID: #extension.id#' );
            print.yellowLine( 'Latest version: #extension.latestVersion.version#  (#extension.latestVersion.provider#)' );
            print.line();
        }
    }

    function providersComplete() {
        return lexService.getProviders().map( ( p ) => p.name );
    }

}
