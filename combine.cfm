<cfsetting showdebugoutput="false" />
<cfapplication name="combine" />
<cfsetting enablecfoutputonly="true" />
<cfscript>
/*
	Create the combine object, or use the cached version

	Required Arguments:
		@enableSCache:				true: cache combined/compressed files on the server, false: re-combine on each request
		@cachePath:					where should the cached combined files be stored on the server?
		@enableCCache:				enable client-side cache (via etags and/or last-modified headers)
		@compressJS:				compress Javascript using YUI compressor or JSMin?
		@compressCSS:				compress CSS using YUI CSS compressor

	Optional Arguments:
		@outputSeperator			character to use to seperate the output of different file content (default = \n)
		@skipMissingFiles:		true: ignore file-not-found errors, false: throw errors when a requested file cannot be found (default = true)
		@getFileModifiedMethod:	'java' or 'com'. Which method to use to obtain the last modified dates of local files. Java is the recommended and default option.
*/

variables.sKey = 'combine_#hash(getCurrentTemplatePath())#';
if((not isDefined('application')) or (not structKeyExists(application, variables.sKey)) or structKeyExists(url, 'reinit')) {
	variables.oCombine = createObject("component", "combine").init(
		enableSCache: true,
		cachePath: expandPath('combine_cache'),
		enableCCache: true,
		compressJS: true,
		compressCSS: true,
		skipMissingFiles: false
	);
	// cache the object in the application scope, if we have an application scope!
	if(isDefined('application')) {
		application[variables.sKey] = variables.oCombine;
	}
} else {
	// get cached object from application scope
	variables.oCombine = application[variables.sKey];
}

/*	Make sure we have the required paths (files to combine) in the url */
if(not structKeyExists(url, 'files')) {
	return;
}

/*	Combine the files, and handle any errors in an appropriate way for the current app */
try {
	arguments = StructNew();
	arguments.files = url.files;
	if (structKeyExists(url, 'delimiter'))
		arguments.delimiter = url.delimiter;
	if (structKeyExists(url, 'enableSCache'))
		arguments.bSCache = url.enableSCache;
	if (structKeyExists(url, 'enableCCache'))
		arguments.bCCache = url.enableCCache;
	if (structKeyExists(url, 'compressJS'))
		arguments.bCompressJS = url.compressJS;
	if (structKeyExists(url, 'compressCSS'))
		arguments.bCompressCSS = url.compressCSS;
	if (structKeyExists(url, 'skipMissingFiles'))
		arguments.bSkipMissingFiles = url.skipMissingFiles;

	variables.oCombine.combine(arguments);
} catch(any e) {
	handleError(e);
}
</cfscript>

<cffunction name="handleError" access="public" returntype="void" output="false">
	<cfargument name="cfcatch" type="any" required="true" />

	<!--- Put any custom error handling here e.g. --->
	<cfdump var="#cfcatch#" />
	<cflog file="combine" text="Fault caught by 'combine'" />
	<cfabort />

</cffunction>