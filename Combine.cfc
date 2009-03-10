<cfcomponent displayname="Combine" output="false" hint="provides javascript and css file merge and compress functionality, to reduce the overhead caused by file sizes & multiple requests">

	<cffunction name="init" access="public" returntype="Combine" output="false">
		<cfargument name="enableSCache" type="boolean" required="true" />
		<cfargument name="cachePath" type="string" required="true" />
		<cfargument name="enableCCache" type="boolean" required="true" />
		<cfargument name="compressJS" type="boolean" required="true" hint="compress JavaScript?" />
		<cfargument name="compressCSS" type="boolean" required="true" hint="compress CSS?" />
		<!--- optional args --->
		<cfargument name="outputSeperator" type="string" required="false" default="#chr(13)#" hint="seperates the output of different file content" />
		<cfargument name="skipMissingFiles" type="boolean" required="false" default="true" hint="skip files that don't exists? If false, non-existent files will cause an error" />
		<cfargument name="getFileModifiedMethod" type="string" required="false" default="java" hint="java or com. Which technique to use to get the last modified times for files." />

		<cfscript>
		variables.sCachePath = arguments.cachePath;
		// enable server-side caching
		variables.bSCache = arguments.enableSCache;
		// enable client-side cacheing via etags and last-modified headers
		variables.bCCache = arguments.enableCCache;
		// enable compression of javascript
		variables.bCompressJS = arguments.compressJS;
		// enable css compression
		variables.bCompressCss = arguments.compressCSS;
		// text used to delimit the merged files in the final output
		variables.sOutputDelimiter = arguments.outputSeperator;
		// skip files that don't exists? If false, non-existent files will cause an error
		variables.bSkipMissingFiles = arguments.skipMissingFiles;

		// -----------------------------------------------------------------------
		variables.jOutputStream = createObject("java","java.io.ByteArrayOutputStream");
		variables.jStringReader = createObject("java","java.io.StringReader");
		variables.jStringWriter = createObject("java","java.io.StringWriter");

		// determine which method to use for getting the file last modified dates
		if(arguments.getFileModifiedMethod eq 'com')	{
			variables.fso = CreateObject("COM", "Scripting.FileSystemObject");
			// calls to getFileDateLastModified() are handled by getFileDateLastModified_com()
			variables.getFileDateLastModified = variables.getFileDateLastModified_com;
		} else {
			variables.jFile = CreateObject("java", "java.io.File");
			// calls to getFileDateLastModified() are handled by getFileDateLastModified_java()
			variables.getFileDateLastModified = variables.getFileDateLastModified_java;
		}
		</cfscript>

		<!--- Ensure server-side cache directory exists --->
		<cfif variables.bSCache and not DirectoryExists(variables.sCachePath)>
			<cfdirectory action="create" directory="#variables.sCachePath#" />
		</cfif>

		<cfreturn this />
	</cffunction>

	<cffunction name="combine" access="public" returntype="void" output="true" hint="combines a list js or css files into a single file, which is output, and cached if caching is enabled">
		<cfargument name="arguments" type="struct" required="true" hint="Structure containing arguments" />

		<cfscript>
		var sType = '';
		var lastModified = 0;
		var lastModifiedDTO = '';
		var sFilePath = '';
		var sCorrectedFilePaths = '';
		var i = 0;
		var sDelimiter = '';

		var etag = '';
		var sCacheFile = '';
		var sOutput = '';
		var sFileContent = '';
		var bIsCompressed = '';

		var filePaths = '';
		</cfscript>

		<cfparam name="arguments.files" type="string" />
		<cfparam name="arguments.delimiter" type="string" default="," />
		<cfparam name="arguments.bSCache" type="boolean" default="#variables.bSCache#" />
		<cfparam name="arguments.bCCache" type="boolean" default="#variables.bCCache#" />
		<cfparam name="arguments.bCompressJS" type="boolean" default="#variables.bCompressJS#" />
		<cfparam name="arguments.bCompressCSS" type="boolean" default="#variables.bCompressCSS#" />
		<cfparam name="arguments.bSkipMissingFiles" type="boolean" default="#variables.bSkipMissingFiles#" />

		<cfscript>
		sDelimiter = arguments.delimiter;
		filePaths = convertToAbsolutePaths(files, sDelimiter);

		// determine what file type we are dealing with
		sType = listLast( listFirst(filePaths, sDelimiter) , '.');
		if (not listFindNoCase('js,css', sType)) {
			throw("combine.invalidFileType", "Only JavaScript and CSS files can be combined.");
		}

		// determine if output should be compressed
		bIsCompressed = IIf(sType eq 'js', arguments.bCompressJS, arguments.bCompressCSS);

		</cfscript>

		<!--- get the latest last modified date --->
		<cfset sCorrectedFilePaths = '' />
		<cfloop from="1" to="#listLen(filePaths, sDelimiter)#" index="i">

			<cfset sFilePath = listGetAt(filePaths, i, sDelimiter) />

			<cfif fileExists( sFilePath )>

				<cfset lastModified = max(lastModified, getFileDateLastModified( sFilePath )) />
				<cfset sCorrectedFilePaths = listAppend(sCorrectedFilePaths, sFilePath, sDelimiter) />

			<cfelseif not arguments.bSkipMissingFiles>
				<cfthrow type="combine.missingFileException" message="A file specified in the combine (#sType#) path doesn't exist." detail="file: #sFilePath#" extendedinfo="full combine path list: #filePaths#" />
			</cfif>

		</cfloop>

		<cfset filePaths = sCorrectedFilePaths />

		<!--- create a string to be used as an Etag - in the response header --->
		<cfset etag = lastModified & '-' & hash(filePaths & bIsCompressed) />

		<!--- Convert Unix epoch timestamp to ColdFusion date/time object --->
		<cfset lastModifiedDTO = DateAdd("s", lastModified / 1000, DateConvert("utc2Local", "January 1 1970 00:00")) />

		<!---
			output the cache headers, this allows the browser to make conditional requests
			(i.e. browser says to server: only return me the file if your eTag is different to mine)
		--->
		<cfif arguments.bCCache>
			<cfheader name="ETag" value="""#etag#""" />
 			<cfheader name="Last-Modified" value="#GetHTTPTimeString(lastModifiedDTO)#" />
		</cfif>

		<!---
			if the browser is doing a conditional request, then only send it the file if the browser's
			etag doesn't match the server's etag (i.e. the browser's file is different to the server's)
		 --->
		<cfif arguments.bCCache and not structKeyExists(url, 'reinit') and ((structKeyExists(cgi, 'HTTP_IF_NONE_MATCH') and cgi.HTTP_IF_NONE_MATCH contains eTag) or
				(structKeyExists(GetHttpRequestData().headers, 'If-Modified-Since') and lastModifiedDTO lte DateConvert("utc2local", ParseDateTime(GetHttpRequestData().headers["If-Modified-Since"])) )) >
			<!--- nothing has changed, return nothing --->
			<cfheader statuscode="304" statustext="Not Modified" />

			<!--- Seems to cause problems with IE and last-modified
			<cfheader name="Content-Length" value="0" /> --->
			<cfreturn />
		<cfelse>
			<!--- first time visit, or files have changed --->

			<cfset sCacheFile = variables.sCachePath & '\' & etag & '.' & sType />

			<cfif arguments.bSCache and not structKeyExists(url, 'reinit')>

				<!--- try to return a cached version of the file --->
				<cfif fileExists(sCacheFile)>
					<cffile action="read" file="#sCacheFile#" variable="sOutput" />
					<!--- output contents --->
					<cfset outputContent(sOutput, sType) />
					<cfreturn />
				</cfif>

			</cfif>

			<!--- combine the file contents into 1 string --->
			<cfset sOutput = '' />
			<cfloop from="1" to="#listLen(filePaths, sDelimiter)#" index="i">
				<cfset sFilePath = listGetAt(filePaths, i, sDelimiter) />

				<cfif not listFindNoCase('js,css', listLast(sFilePath, '.'))>
					<cfthrow type="combine.invalidFileType" message="Only JavaScript and CSS files can be combined." />
				</cfif>

				<cffile action="read" variable="sFileContent" file="#sFilePath#" />
				<cfset sOutput = sOutput & variables.sOutputDelimiter & sFileContent />
			</cfloop>

			<cfscript>
			// Compress the javascript and CSS if requested
			if (sType eq 'js' and bIsCompressed) {
				sOutput = compressJsWithYUI(sOutput);
			} else if(sType eq 'css' and bIsCompressed) {
				sOutput = compressCssWithYUI(sOutput);
			}

			//output contents
			outputContent(sOutput, sType);
			</cfscript>

			<!--- write the cache file --->
			<cfif arguments.bSCache>
				<cffile action="write" file="#sCacheFile#" output="#sOutput#" />
			</cfif>

		</cfif>

	</cffunction>


	<cffunction name="outputContent" access="private" returnType="void" output="true">
		<cfargument name="sOut" type="string" required="true" />
		<cfargument name="sType" type="string" required="true" />

		<cfset var mimeType = '' />

		<cfif arguments.sType is "js">
			<cfset mimeType = "application/javascript" />
		<cfelseif arguments.sType is "css">
			<cfset mimeType = "text/css" />
		</cfif>

<!--- 		<cfheader name="Content-Length" value="#Len(arguments.sOut)#" /> --->

		<cfcontent type="#mimeType#" />
		<cfoutput>#arguments.sOut#</cfoutput>

	</cffunction>


	<!--- uses 'Scripting.FileSystemObject' com object --->
	<cffunction name="getFileDateLastModified_com" access="private" returnType="string">
		<cfargument name="path" type="string" required="true" />
		<cfset var file = variables.fso.GetFile(arguments.path) />
		<cfreturn file.DateLastModified />
	</cffunction>
	<!--- uses 'java.io.file'. Recommended --->
	<cffunction name="getFileDateLastModified_java" access="private" returnType="string">
		<cfargument name="path" type="string" required="true" />
		<cfset var file = variables.jFile.init(arguments.path) />
		<cfreturn file.lastModified() />
	</cffunction>


	<cffunction name="compressJsWithJSMin" access="private" returnType="string" hint="takes a javascript string and returns a compressed version, using JSMin">
		<cfargument name="sInput" type="string" required="true" />
		<cfscript>
		var sOut = arguments.sInput;
		var joOutput = '';
		var joInput = '';
		var joJSMin = '';

		if (not structKeyExists(variables, "jJSMin")) {
			variables.jJSMin = createObject("java","com.magnoliabox.jsmin.JSMin");
		}

		joOutput = variables.jOutputStream.init();
		joInput = variables.jStringReader.init(sOut);
		joJSMin = variables.jJSMin.init(joInput, joOutput);

		joJSMin.jsmin();
		joInput.close();
		sOut = joOutput.toString();
		joOutput.close();

		return sOut;
		</cfscript>
	</cffunction>


	<cffunction name="compressJsWithYUI" access="private" returnType="string" hint="takes a javascript string and returns a compressed version, using the YUI javascript compressor">
		<cfargument name="sInput" type="string" required="true" />
		<cfscript>

		var sOut = arguments.sInput;
		var joInput = '';
		var joOutput = '';
		var joErrorReporter = '';
		var joYUI = '';

		if (not structKeyExists(variables, "jYuiJavaScriptCompressor")) {
			variables.jYuiJavaScriptCompressor = createObject("java","com.yahoo.platform.yui.compressor.JavaScriptCompressor");
			variables.jErrorReporter = createObject("java","org.mozilla.javascript.ErrorReporter");
		}

		joInput = variables.jStringReader.init(sOut);
		joOutput = variables.jStringWriter.init();
		joErrorReporter = variables.jErrorReporter;
		joYUI = variables.jYuiJavaScriptCompressor.init(joInput, joErrorReporter);

		// compress(out, linebreak, munge, verbose, preserveAllSemiColons, disableOptimizations)
		joYUI.compress(joOutput, javaCast('int',-1), javaCast('boolean', true), javaCast('boolean', false), javaCast('boolean', true), javaCast('boolean', false));
		joInput.close();
		sOut = joOutput.toString();
		joOutput.close();

		return sOut;

		</cfscript>
	</cffunction>


	<cffunction name="compressCssWithYUI" access="private" returnType="string" hint="takes a css string and returns a compressed version, using the YUI css compressor">
		<cfargument name="sInput" type="string" required="true" />
		<cfscript>
		var sOut = arguments.sInput;
		var joInput = '';
		var joOutput = '';
		var joYUI = '';

		if(not structKeyExists(variables, "jYuiCssCompressor")) {
			variables.jYuiCssCompressor = createObject("java","com.yahoo.platform.yui.compressor.CssCompressor");
		}

		joInput = variables.jStringReader.init(sOut);
		joOutput = variables.jStringWriter.init();
		joYUI = variables.jYuiCssCompressor.init(joInput);

		joYUI.compress(joOutput, javaCast('int',-1));
		joInput.close();
		sOut = joOutput.toString();
		joOutput.close();

		return sOut;
		</cfscript>
	</cffunction>


	<cffunction name="convertToAbsolutePaths" access="private" returnType="string"output="false" hint="takes a list of relative paths and makes them absolute, using expandPath">
		<cfargument name="relativePaths" type="string" required="true" hint="delimited list of relative paths" />
		<cfargument name="delimiter" type="string" required="false" default="," hint="the delimiter used in the provided paths string" />

		<cfset var filePaths = '' />
		<cfset var path = '' />

		<cfloop list="#arguments.relativePaths#" delimiters="#arguments.delimiter#" index="path">
			<cfset filePaths = listAppend(filePaths, expandPath(path), arguments.delimiter) />
		</cfloop>

		<cfreturn filePaths />
	</cffunction>

	<cffunction name="throw" returntype="void" output="no" access="public">
		<cfargument name="exceptionType" type="string" required="true" />
		<cfargument name="message" type="string" required="false" default="" />
		<cfargument name="detail" type="string" required="false" default="" />
		<cfargument name="extendedInfo" type="string" required="false" default="" />

		<cfthrow type="#Arguments.exceptionType#" message="#Arguments.message#" detail="#Arguments.detail#" extendedinfo="#Arguments.extendedInfo#" />
	</cffunction>

</cfcomponent>
