<?xml version="1.0" encoding="UTF-8"?>
<!--
  openapi2dita: OpenAPI 3.x / Swagger 2.0 to DITA map and topics.

  Input:  the API description as a JSON string in $json (YAML is converted to JSON
          by the Ant task before this stylesheet runs).
  Output: written with xsl:result-document relative to the base output URI:
            {map-name}.ditamap
            overview.dita
            tags/*.dita         (one concept per tag that has a description)
            operations/*.dita   (one reference topic per operation)
            schemas/*.dita      (one reference topic per named schema)
  Entry:  call the named template "main".
-->
<xsl:stylesheet version="3.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema"
  xmlns:j="http://www.w3.org/2005/xpath-functions"
  xmlns:oa="urn:openapi2dita"
  xmlns:md="urn:openapi2dita:markdown"
  exclude-result-prefixes="#all"
  expand-text="yes">

  <xsl:param name="json" as="xs:string"/>
  <xsl:param name="map-name" as="xs:string" select="'api'"/>
  <xsl:param name="lang" as="xs:string" select="'en-US'"/>
  <!-- tag | path | none -->
  <xsl:param name="group-by" as="xs:string" select="'tag'"/>
  <xsl:param name="include-curl" as="xs:string" select="'yes'"/>
  <xsl:param name="include-schemas" as="xs:string" select="'yes'"/>

  <xsl:output name="map" method="xml" indent="yes" encoding="UTF-8"
    doctype-public="-//OASIS//DTD DITA Map//EN" doctype-system="map.dtd"/>
  <xsl:output name="concept" method="xml" indent="yes" encoding="UTF-8"
    doctype-public="-//OASIS//DTD DITA Concept//EN" doctype-system="concept.dtd"
    suppress-indentation="p li dd dt stentry codeblock shortdesc title navtitle note"/>
  <xsl:output name="reference" method="xml" indent="yes" encoding="UTF-8"
    doctype-public="-//OASIS//DTD DITA Reference//EN" doctype-system="reference.dtd"
    suppress-indentation="p li dd dt stentry codeblock shortdesc title navtitle note"/>

  <!-- ===================================================================== -->
  <!-- Globals                                                               -->
  <!-- ===================================================================== -->

  <xsl:variable name="doc" select="json-to-xml($json, map{'duplicates':'use-first'})"/>
  <xsl:variable name="root" as="element(j:map)" select="$doc/j:map"/>
  <xsl:variable name="is-v2" as="xs:boolean" select="exists($root/j:string[@key='swagger'])"/>
  <xsl:variable name="info" select="$root/j:map[@key='info']"/>
  <xsl:variable name="methods" select="('get','put','post','delete','options','head','patch','trace')"/>
  <xsl:variable name="operations" as="element(j:map)*"
    select="$root/j:map[@key=('paths','webhooks')]/j:map/j:map[@key = $methods]"/>
  <xsl:variable name="schemas" as="element(j:map)?"
    select="if ($is-v2) then $root/j:map[@key='definitions']
            else $root/j:map[@key='components']/j:map[@key='schemas']"/>
  <xsl:variable name="schema-prefix" select="if ($is-v2) then '#/definitions/' else '#/components/schemas/'"/>
  <xsl:variable name="security-schemes" as="element(j:map)?"
    select="if ($is-v2) then $root/j:map[@key='securityDefinitions']
            else $root/j:map[@key='components']/j:map[@key='securitySchemes']"/>
  <xsl:variable name="write-schemas" as="xs:boolean" select="$include-schemas = ('yes','true') and exists($schemas/j:map)"/>
  <xsl:variable name="NL" select="'&#10;'"/>

  <xsl:key name="refs" match="j:string[@key='$ref']" use="string(.)"/>

  <!-- Unique, file-system-safe ids for operations (keyed by generate-id) -->
  <xsl:variable name="op-ids" as="map(xs:string, xs:string)">
    <xsl:map>
      <xsl:for-each-group select="$operations" group-by="lower-case(oa:op-base-id(.))">
        <xsl:for-each select="current-group()">
          <xsl:map-entry key="generate-id(.)"
            select="if (position() eq 1) then oa:op-base-id(.) else oa:op-base-id(.) || '_' || position()"/>
        </xsl:for-each>
      </xsl:for-each-group>
    </xsl:map>
  </xsl:variable>

  <!-- Unique ids for schemas, keyed by schema name -->
  <xsl:variable name="schema-ids" as="map(xs:string, xs:string)">
    <xsl:map>
      <xsl:for-each-group select="$schemas/j:map" group-by="lower-case(oa:ncname(@key))">
        <xsl:for-each select="current-group()">
          <xsl:map-entry key="string(@key)"
            select="if (position() eq 1) then oa:ncname(@key) else oa:ncname(@key) || '_' || position()"/>
        </xsl:for-each>
      </xsl:for-each-group>
    </xsl:map>
  </xsl:variable>

  <xsl:variable name="default-server" as="xs:string" select="oa:server-url($root)"/>

  <!-- ===================================================================== -->
  <!-- Entry point                                                           -->
  <!-- ===================================================================== -->

  <xsl:template name="main">
    <xsl:message>OpenAPI: {if ($is-v2) then 'Swagger ' || $root/j:string[@key='swagger'] else 'OpenAPI ' || $root/j:string[@key='openapi']}, {count($operations)} operations, {count($schemas/j:map)} schemas</xsl:message>
    <xsl:call-template name="write-map"/>
    <xsl:call-template name="write-overview"/>
    <xsl:for-each select="$operations">
      <xsl:call-template name="write-operation"/>
    </xsl:for-each>
    <xsl:if test="$write-schemas">
      <xsl:for-each select="$schemas/j:map">
        <xsl:call-template name="write-schema"/>
      </xsl:for-each>
    </xsl:if>
  </xsl:template>

  <!-- ===================================================================== -->
  <!-- Map                                                                   -->
  <!-- ===================================================================== -->

  <xsl:template name="write-map">
    <xsl:result-document href="{$map-name}.ditamap" format="map">
      <map xml:lang="{$lang}">
        <title>{oa:api-title()}</title>
        <topicref href="overview.dita" type="concept"/>
        <xsl:choose>
          <xsl:when test="$group-by = 'none'">
            <topichead>
              <topicmeta><navtitle>Operations</navtitle></topicmeta>
              <xsl:for-each select="$operations">
                <topicref href="operations/{oa:op-id(.)}.dita" type="reference"/>
              </xsl:for-each>
            </topichead>
          </xsl:when>
          <xsl:otherwise>
            <xsl:for-each-group select="$operations" group-by="oa:group-key(.)">
              <xsl:sort select="oa:group-order(current-grouping-key())" data-type="number"/>
              <xsl:variable name="key" select="current-grouping-key()"/>
              <xsl:variable name="tag" select="$root/j:array[@key='tags']/j:map[j:string[@key='name'] = $key]"/>
              <xsl:choose>
                <xsl:when test="$group-by = 'tag' and $tag[j:string[@key='description'] or j:map[@key='externalDocs']]">
                  <xsl:variable name="tag-id" select="oa:tag-id($key)"/>
                  <xsl:call-template name="write-tag-topic">
                    <xsl:with-param name="tag" select="$tag"/>
                    <xsl:with-param name="id" select="$tag-id"/>
                  </xsl:call-template>
                  <topicref href="tags/{$tag-id}.dita" type="concept">
                    <xsl:for-each select="current-group()">
                      <topicref href="operations/{oa:op-id(.)}.dita" type="reference"/>
                    </xsl:for-each>
                  </topicref>
                </xsl:when>
                <xsl:otherwise>
                  <topichead>
                    <topicmeta><navtitle>{oa:group-title($key, $tag)}</navtitle></topicmeta>
                    <xsl:for-each select="current-group()">
                      <topicref href="operations/{oa:op-id(.)}.dita" type="reference"/>
                    </xsl:for-each>
                  </topichead>
                </xsl:otherwise>
              </xsl:choose>
            </xsl:for-each-group>
          </xsl:otherwise>
        </xsl:choose>
        <xsl:if test="$write-schemas">
          <topichead>
            <topicmeta><navtitle>Data models</navtitle></topicmeta>
            <xsl:for-each select="$schemas/j:map">
              <topicref href="schemas/{$schema-ids(string(@key))}.dita" type="reference"/>
            </xsl:for-each>
          </topichead>
        </xsl:if>
      </map>
    </xsl:result-document>
  </xsl:template>

  <xsl:function name="oa:group-key" as="xs:string">
    <xsl:param name="op" as="element(j:map)"/>
    <xsl:choose>
      <xsl:when test="oa:is-webhook($op)">#webhooks</xsl:when>
      <xsl:when test="$group-by = 'path'">
        <xsl:variable name="seg" select="tokenize($op/../@key, '/')[normalize-space()][1]"/>
        <xsl:sequence select="if ($seg) then '/' || $seg else '/'"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:sequence select="string(($op/j:array[@key='tags']/j:string)[1])"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:function>

  <xsl:function name="oa:group-order" as="xs:integer">
    <xsl:param name="key" as="xs:string"/>
    <xsl:variable name="declared" select="$root/j:array[@key='tags']/j:map/j:string[@key='name']/string()"/>
    <xsl:sequence select="if ($key = '#webhooks') then 300000
                          else if ($key = '') then 200000
                          else if ($group-by = 'tag' and $key = $declared) then index-of($declared, $key)[1]
                          else 100000"/>
  </xsl:function>

  <xsl:function name="oa:group-title" as="xs:string">
    <xsl:param name="key" as="xs:string"/>
    <xsl:param name="tag" as="element()?"/>
    <xsl:sequence select="if ($key = '#webhooks') then 'Webhooks'
                          else if ($key = '' and empty($operations[not(oa:is-webhook(.))]/j:array[@key='tags']/j:string)) then 'Operations'
                          else if ($key = '') then 'Other operations'
                          else ($tag/j:string[@key='x-displayName'], $key)[1]"/>
  </xsl:function>

  <xsl:function name="oa:is-webhook" as="xs:boolean">
    <xsl:param name="op" as="element()"/>
    <xsl:sequence select="$op/../../@key = 'webhooks' and empty($op/../../../parent::*)"/>
  </xsl:function>

  <xsl:function name="oa:tag-id" as="xs:string">
    <xsl:param name="name" as="xs:string"/>
    <xsl:sequence select="'tag_' || oa:ncname($name)"/>
  </xsl:function>

  <!-- ===================================================================== -->
  <!-- Overview topic                                                        -->
  <!-- ===================================================================== -->

  <xsl:template name="write-overview">
    <xsl:result-document href="overview.dita" format="concept">
      <concept id="overview" xml:lang="{$lang}">
        <title>{oa:api-title()}</title>
        <xsl:if test="$info/j:string[@key='summary']">
          <shortdesc>{normalize-space($info/j:string[@key='summary'])}</shortdesc>
        </xsl:if>
        <conbody>
          <xsl:sequence select="oa:md($info/j:string[@key='description'], 'body')"/>

          <section id="about">
            <title>About this API</title>
            <dl>
              <xsl:if test="$info/*[@key='version']">
                <dlentry><dt>Version</dt><dd>{$info/*[@key='version']}</dd></dlentry>
              </xsl:if>
              <dlentry>
                <dt>Specification</dt>
                <dd>{if ($is-v2) then 'Swagger ' || $root/*[@key='swagger'] else 'OpenAPI ' || $root/*[@key='openapi']}</dd>
              </dlentry>
              <xsl:for-each select="$info/j:map[@key='contact'][*]">
                <dlentry>
                  <dt>Contact</dt>
                  <dd>
                    <xsl:value-of select="j:string[@key='name']"/>
                    <xsl:for-each select="j:string[@key='email']">
                      <xsl:if test="../j:string[@key='name']">, </xsl:if>
                      <xref href="mailto:{.}" scope="external" format="email">{.}</xref>
                    </xsl:for-each>
                    <xsl:for-each select="j:string[@key='url']">
                      <xsl:if test="../j:string[@key=('name','email')]">, </xsl:if>
                      <xsl:sequence select="oa:ext-link(., ())"/>
                    </xsl:for-each>
                  </dd>
                </dlentry>
              </xsl:for-each>
              <xsl:for-each select="$info/j:map[@key='license']">
                <dlentry>
                  <dt>License</dt>
                  <dd><xsl:sequence select="oa:ext-link(j:string[@key='url'], j:string[@key='name'])"/></dd>
                </dlentry>
              </xsl:for-each>
              <xsl:for-each select="$info/j:string[@key='termsOfService']">
                <dlentry><dt>Terms of service</dt><dd><xsl:sequence select="oa:ext-link(., ())"/></dd></dlentry>
              </xsl:for-each>
              <xsl:for-each select="$root/j:map[@key='externalDocs']">
                <dlentry>
                  <dt>More information</dt>
                  <dd><xsl:sequence select="oa:ext-link(j:string[@key='url'], j:string[@key='description'])"/></dd>
                </dlentry>
              </xsl:for-each>
            </dl>
          </section>

          <xsl:call-template name="servers-section"/>
          <xsl:call-template name="security-schemes-section"/>
        </conbody>
      </concept>
    </xsl:result-document>
  </xsl:template>

  <xsl:template name="servers-section">
    <xsl:choose>
      <xsl:when test="$is-v2 and $root/j:string[@key='host']">
        <section id="servers">
          <title>Base URL</title>
          <p><codeph>{$default-server}</codeph></p>
        </section>
      </xsl:when>
      <xsl:when test="$root/j:array[@key='servers']/j:map">
        <section id="servers">
          <title>Servers</title>
          <ul>
            <xsl:for-each select="$root/j:array[@key='servers']/j:map">
              <li>
                <p><codeph>{j:string[@key='url']}</codeph>
                  <xsl:if test="j:string[@key='description']"> - {normalize-space(j:string[@key='description'])}</xsl:if></p>
                <xsl:if test="j:map[@key='variables']/j:map">
                  <ul>
                    <xsl:for-each select="j:map[@key='variables']/j:map">
                      <li>
                        <codeph>{@key}</codeph>
                        <xsl:if test="*[@key='default']"> (default <codeph>{*[@key='default']}</codeph>)</xsl:if>
                        <xsl:if test="j:array[@key='enum']">: one of <xsl:sequence select="oa:codeph-list(j:array[@key='enum']/*)"/></xsl:if>
                        <xsl:if test="j:string[@key='description']">. {normalize-space(j:string[@key='description'])}</xsl:if>
                      </li>
                    </xsl:for-each>
                  </ul>
                </xsl:if>
              </li>
            </xsl:for-each>
          </ul>
        </section>
      </xsl:when>
    </xsl:choose>
  </xsl:template>

  <xsl:template name="security-schemes-section">
    <xsl:if test="$security-schemes/j:map">
      <section id="authentication">
        <title>Authentication</title>
        <dl>
          <xsl:for-each select="$security-schemes/j:map">
            <xsl:variable name="s" select="oa:resolve(.)"/>
            <dlentry>
              <dt>{@key}</dt>
              <dd>
                <p>{oa:scheme-summary($s)}</p>
                <xsl:sequence select="oa:md($s/j:string[@key='description'], 'body')"/>
                <xsl:call-template name="oauth-flows">
                  <xsl:with-param name="s" select="$s"/>
                </xsl:call-template>
              </dd>
            </dlentry>
          </xsl:for-each>
        </dl>
        <xsl:variable name="global" select="$root/j:array[@key='security']"/>
        <xsl:if test="$global/j:map[*]">
          <p>Unless an operation says otherwise, requests must use:</p>
          <xsl:sequence select="oa:security-list($global, '')"/>
        </xsl:if>
      </section>
    </xsl:if>
  </xsl:template>

  <xsl:template name="oauth-flows">
    <xsl:param name="s" as="element()"/>
    <xsl:variable name="flows" as="element()*"
      select="if ($is-v2 and $s/j:string[@key='type'] = 'oauth2') then $s
              else $s/j:map[@key='flows']/j:map"/>
    <xsl:if test="$flows">
      <ul>
        <xsl:for-each select="$flows">
          <li>
            <p>Flow: <codeph>{if ($is-v2) then j:string[@key='flow'] else @key}</codeph></p>
            <xsl:for-each select="j:string[@key=('authorizationUrl','tokenUrl','refreshUrl')]">
              <p>{oa:label-for-key(@key)}: <codeph>{.}</codeph></p>
            </xsl:for-each>
            <xsl:if test="j:map[@key='scopes']/j:string">
              <p>Scopes:</p>
              <ul>
                <xsl:for-each select="j:map[@key='scopes']/j:string">
                  <li><codeph>{@key}</codeph><xsl:if test="normalize-space(.)"> - {normalize-space(.)}</xsl:if></li>
                </xsl:for-each>
              </ul>
            </xsl:if>
          </li>
        </xsl:for-each>
      </ul>
    </xsl:if>
  </xsl:template>

  <xsl:function name="oa:label-for-key" as="xs:string">
    <xsl:param name="k" as="xs:string"/>
    <xsl:sequence select="map{'authorizationUrl':'Authorization URL','tokenUrl':'Token URL','refreshUrl':'Refresh URL'}($k)"/>
  </xsl:function>

  <xsl:function name="oa:scheme-summary" as="xs:string">
    <xsl:param name="s" as="element()"/>
    <xsl:variable name="type" select="string($s/j:string[@key='type'])"/>
    <xsl:sequence select="
      if ($type = 'apiKey') then 'API key sent in the ' || $s/j:string[@key='in'] || ' parameter ' || $s/j:string[@key='name'] || '.'
      else if ($type = 'http' and lower-case($s/j:string[@key='scheme']) = 'bearer')
        then 'HTTP bearer token' || (if ($s/j:string[@key='bearerFormat']) then ' (' || $s/j:string[@key='bearerFormat'] || ')' else '') || ' in the Authorization header.'
      else if ($type = 'http') then 'HTTP ' || $s/j:string[@key='scheme'] || ' authentication.'
      else if ($type = 'basic') then 'HTTP basic authentication.'
      else if ($type = 'oauth2') then 'OAuth 2.0.'
      else if ($type = 'openIdConnect') then 'OpenID Connect. Discovery URL: ' || $s/j:string[@key='openIdConnectUrl']
      else if ($type = 'mutualTLS') then 'Mutual TLS.'
      else $type"/>
  </xsl:function>

  <!-- ===================================================================== -->
  <!-- Tag topic                                                             -->
  <!-- ===================================================================== -->

  <xsl:template name="write-tag-topic">
    <xsl:param name="tag" as="element()"/>
    <xsl:param name="id" as="xs:string"/>
    <xsl:result-document href="tags/{$id}.dita" format="concept">
      <concept id="{$id}" xml:lang="{$lang}">
        <title>{oa:group-title(string($tag/j:string[@key='name']), $tag)}</title>
        <conbody>
          <xsl:sequence select="oa:md($tag/j:string[@key='description'], 'body')"/>
          <xsl:for-each select="$tag/j:map[@key='externalDocs']">
            <p>See also: <xsl:sequence select="oa:ext-link(j:string[@key='url'], j:string[@key='description'])"/></p>
          </xsl:for-each>
        </conbody>
      </concept>
    </xsl:result-document>
  </xsl:template>

  <!-- ===================================================================== -->
  <!-- Operation topic                                                       -->
  <!-- ===================================================================== -->

  <xsl:template name="write-operation">
    <xsl:variable name="op" select="."/>
    <xsl:variable name="id" select="oa:op-id(.)"/>
    <xsl:variable name="method" select="upper-case(@key)"/>
    <xsl:variable name="path" select="string(../@key)"/>
    <xsl:variable name="params" select="oa:op-parameters(.)"/>
    <xsl:variable name="server" select="oa:op-server(.)"/>
    <xsl:result-document href="operations/{$id}.dita" format="reference">
      <reference id="{$id}" xml:lang="{$lang}">
        <title>{oa:op-title(.)}</title>
        <xsl:choose>
          <xsl:when test="oa:is-webhook(.)">
            <shortdesc>Webhook <codeph>{$path}</codeph>: the API sends a <codeph>{$method}</codeph> request to your registered URL.</shortdesc>
          </xsl:when>
          <xsl:otherwise>
            <shortdesc><codeph>{$method} {$path}</codeph></shortdesc>
          </xsl:otherwise>
        </xsl:choose>
        <prolog>
          <metadata>
            <xsl:if test="j:array[@key='tags']/j:string">
              <keywords>
                <xsl:for-each select="j:array[@key='tags']/j:string"><keyword>{.}</keyword></xsl:for-each>
              </keywords>
            </xsl:if>
            <othermeta name="http-method" content="{$method}"/>
            <othermeta name="{if (oa:is-webhook(.)) then 'webhook' else 'path'}" content="{$path}"/>
            <xsl:if test="j:string[@key='operationId']">
              <othermeta name="operationId" content="{j:string[@key='operationId']}"/>
            </xsl:if>
          </metadata>
        </prolog>
        <refbody>
          <xsl:if test="not(oa:is-webhook(.))">
            <refsyn>
              <codeblock outputclass="language-http">{$method} {$server}{$path}</codeblock>
            </refsyn>
          </xsl:if>

          <xsl:if test="j:boolean[@key='deprecated'] = 'true'">
            <section id="deprecated">
              <note type="attention">This operation is deprecated.</note>
            </section>
          </xsl:if>

          <xsl:variable name="desc" select="(j:string[@key='description'], ../j:string[@key='description'])[1]"/>
          <xsl:if test="normalize-space($desc)">
            <section id="description">
              <xsl:sequence select="oa:md($desc, 'body')"/>
              <xsl:for-each select="j:map[@key='externalDocs']">
                <p>See also: <xsl:sequence select="oa:ext-link(j:string[@key='url'], j:string[@key='description'])"/></p>
              </xsl:for-each>
            </section>
          </xsl:if>

          <xsl:call-template name="security-section"/>

          <xsl:variable name="table-params" select="$params[not(j:string[@key='in'] = ('body','formData'))]"/>
          <xsl:if test="$table-params">
            <section id="parameters">
              <title>Parameters</title>
              <simpletable relcolwidth="2* 1* 2* 1* 5*">
                <sthead>
                  <stentry>Name</stentry><stentry>In</stentry><stentry>Type</stentry>
                  <stentry>Required</stentry><stentry>Description</stentry>
                </sthead>
                <xsl:for-each select="$table-params">
                  <xsl:variable name="schema" select="oa:param-schema(.)"/>
                  <strow>
                    <stentry><codeph>{j:string[@key='name']}</codeph></stentry>
                    <stentry>{j:string[@key='in']}</stentry>
                    <stentry><xsl:sequence select="oa:type-label($schema, '../schemas/', 0)"/></stentry>
                    <stentry>{if (j:boolean[@key='required'] = 'true') then 'Yes' else 'No'}</stentry>
                    <stentry>
                      <xsl:sequence select="oa:md(j:string[@key='description'], 'cell')"/>
                      <xsl:if test="j:boolean[@key='deprecated'] = 'true'"><p><b>Deprecated.</b></p></xsl:if>
                      <xsl:sequence select="oa:schema-notes($schema)"/>
                      <xsl:if test="not($schema/*[@key='example']) and *[@key='example'][self::j:string or self::j:number or self::j:boolean]">
                        <p>Example: <codeph>{*[@key='example']}</codeph></p>
                      </xsl:if>
                    </stentry>
                  </strow>
                </xsl:for-each>
              </simpletable>
            </section>
          </xsl:if>

          <xsl:call-template name="request-body-section">
            <xsl:with-param name="params" select="$params"/>
          </xsl:call-template>

          <xsl:call-template name="responses-section"/>

          <xsl:if test="$include-curl = ('yes','true') and not(oa:is-webhook(.))">
            <example id="example-request">
              <title>Example request</title>
              <codeblock outputclass="language-bash">{oa:curl(., $params, $server)}</codeblock>
            </example>
          </xsl:if>

          <xsl:call-template name="response-example"/>
        </refbody>
        <xsl:variable name="used" select="oa:schemas-used-by-op(.)"/>
        <xsl:if test="$write-schemas and exists($used)">
          <related-links>
            <linklist>
              <title>Data models</title>
              <xsl:for-each select="$used">
                <link href="../schemas/{$schema-ids(.)}.dita" type="reference"/>
              </xsl:for-each>
            </linklist>
          </related-links>
        </xsl:if>
      </reference>
    </xsl:result-document>
  </xsl:template>

  <xsl:template name="security-section">
    <xsl:variable name="sec" select="if (j:array[@key='security']) then j:array[@key='security'] else $root/j:array[@key='security']"/>
    <xsl:if test="exists($sec)">
      <section id="authorization">
        <title>Authorization</title>
        <xsl:choose>
          <xsl:when test="not($sec/j:map[*])">
            <p>No authentication required.</p>
          </xsl:when>
          <xsl:otherwise>
            <xsl:sequence select="oa:security-list($sec, '../overview.dita')"/>
            <xsl:if test="$sec/j:map[not(*)]">
              <p>Authentication is optional.</p>
            </xsl:if>
          </xsl:otherwise>
        </xsl:choose>
      </section>
    </xsl:if>
  </xsl:template>

  <xsl:function name="oa:security-list" as="element()?">
    <xsl:param name="sec" as="element(j:array)"/>
    <xsl:param name="overview" as="xs:string"/>
    <xsl:variable name="reqs" select="$sec/j:map[*]"/>
    <xsl:if test="$reqs">
      <ul>
        <xsl:for-each select="$reqs">
          <li>
            <xsl:if test="position() gt 1">Or: </xsl:if>
            <xsl:for-each select="j:array">
              <xsl:if test="position() gt 1"> and </xsl:if>
              <xref href="{$overview}#overview/authentication" type="section">{@key}</xref>
              <xsl:if test="j:string"> (scopes: <xsl:sequence select="oa:codeph-list(j:string)"/>)</xsl:if>
            </xsl:for-each>
          </li>
        </xsl:for-each>
      </ul>
    </xsl:if>
  </xsl:function>

  <!-- Request body: OpenAPI 3 requestBody, or Swagger 2 body / formData parameters -->
  <xsl:template name="request-body-section">
    <xsl:param name="params" as="element()*"/>
    <xsl:variable name="op" select="."/>
    <xsl:choose>
      <xsl:when test="not($is-v2) and j:map[@key='requestBody']">
        <xsl:variable name="rb" select="oa:resolve(j:map[@key='requestBody'])"/>
        <section id="request-body">
          <title>Request body</title>
          <xsl:sequence select="oa:md($rb/j:string[@key='description'], 'body')"/>
          <p>{if ($rb/j:boolean[@key='required'] = 'true') then 'Required.' else 'Optional.'}</p>
          <xsl:for-each select="$rb/j:map[@key='content']/j:map">
            <xsl:call-template name="media-type-block">
              <xsl:with-param name="media" select="string(@key)"/>
              <xsl:with-param name="schema" select="j:map[@key='schema']"/>
            </xsl:call-template>
          </xsl:for-each>
        </section>
      </xsl:when>
      <xsl:when test="$is-v2 and $params[j:string[@key='in'] = 'body']">
        <xsl:variable name="body" select="$params[j:string[@key='in'] = 'body'][1]"/>
        <section id="request-body">
          <title>Request body</title>
          <xsl:sequence select="oa:md($body/j:string[@key='description'], 'body')"/>
          <p>{if ($body/j:boolean[@key='required'] = 'true') then 'Required.' else 'Optional.'}</p>
          <xsl:call-template name="media-type-block">
            <xsl:with-param name="media" select="string-join(oa:v2-media($op, 'consumes', 'application/json'), ', ')"/>
            <xsl:with-param name="schema" select="$body/j:map[@key='schema']"/>
          </xsl:call-template>
        </section>
      </xsl:when>
      <xsl:when test="$is-v2 and $params[j:string[@key='in'] = 'formData']">
        <section id="request-body">
          <title>Request body</title>
          <p>Content type: <xsl:sequence select="oa:codeph-list(oa:v2-media($op, 'consumes', 'application/x-www-form-urlencoded'))"/></p>
          <simpletable relcolwidth="2* 2* 1* 5*">
            <sthead><stentry>Field</stentry><stentry>Type</stentry><stentry>Required</stentry><stentry>Description</stentry></sthead>
            <xsl:for-each select="$params[j:string[@key='in'] = 'formData']">
              <strow>
                <stentry><codeph>{j:string[@key='name']}</codeph></stentry>
                <stentry><xsl:sequence select="oa:type-label(., '../schemas/', 0)"/></stentry>
                <stentry>{if (j:boolean[@key='required'] = 'true') then 'Yes' else 'No'}</stentry>
                <stentry>
                  <xsl:sequence select="oa:md(j:string[@key='description'], 'cell')"/>
                  <xsl:sequence select="oa:schema-notes(.)"/>
                </stentry>
              </strow>
            </xsl:for-each>
          </simpletable>
        </section>
      </xsl:when>
    </xsl:choose>
  </xsl:template>

  <!-- A media type with its schema: type line, inline property table, example -->
  <xsl:template name="media-type-block">
    <xsl:param name="media" as="xs:string"/>
    <xsl:param name="schema" as="element()?"/>
    <p>Content type: <codeph>{$media}</codeph></p>
    <xsl:if test="$schema">
      <p>Schema: <xsl:sequence select="oa:type-label($schema, '../schemas/', 0)"/></p>
      <xsl:call-template name="inline-properties">
        <xsl:with-param name="schema" select="$schema"/>
        <xsl:with-param name="from" select="'../schemas/'"/>
      </xsl:call-template>
    </xsl:if>
    <xsl:variable name="example" select="oa:media-example(., $schema)"/>
    <xsl:if test="$example">
      <p>Example:</p>
      <codeblock outputclass="{oa:code-class($media)}">{oa:example-text($example, $media)}</codeblock>
    </xsl:if>
  </xsl:template>

  <!-- Property table for an inline (non-$ref) object schema, or array of inline objects -->
  <xsl:template name="inline-properties">
    <xsl:param name="schema" as="element()?"/>
    <xsl:param name="from" as="xs:string"/>
    <xsl:variable name="target" select="
      if ($schema/j:string[@key='$ref']) then ()
      else if ($schema/j:map[@key='items'][not(j:string[@key='$ref'])]) then $schema/j:map[@key='items']
      else $schema"/>
    <xsl:if test="$target and exists(oa:merged-properties($target))">
      <simpletable relcolwidth="2* 2* 1* 5*">
        <sthead><stentry>Property</stentry><stentry>Type</stentry><stentry>Required</stentry><stentry>Description</stentry></sthead>
        <xsl:call-template name="property-rows">
          <xsl:with-param name="schema" select="$target"/>
          <xsl:with-param name="prefix" select="''"/>
          <xsl:with-param name="from" select="$from"/>
          <xsl:with-param name="depth" select="0"/>
        </xsl:call-template>
      </simpletable>
    </xsl:if>
  </xsl:template>

  <xsl:template name="responses-section">
    <xsl:variable name="op" select="."/>
    <xsl:if test="j:map[@key='responses']/j:map">
      <section id="responses">
        <title>Responses</title>
        <simpletable relcolwidth="1* 4* 3*">
          <sthead><stentry>Status</stentry><stentry>Description</stentry><stentry>Response body</stentry></sthead>
          <xsl:for-each select="j:map[@key='responses']/j:map">
            <xsl:variable name="r" select="oa:resolve(.)"/>
            <strow>
              <stentry><codeph>{@key}</codeph>{oa:status-text(@key)}</stentry>
              <stentry>
                <xsl:sequence select="oa:md($r/j:string[@key='description'], 'cell')"/>
                <xsl:if test="$r/j:map[@key='headers']/j:map">
                  <p>Headers:</p>
                  <ul>
                    <xsl:for-each select="$r/j:map[@key='headers']/j:map">
                      <xsl:variable name="h" select="oa:resolve(.)"/>
                      <li><codeph>{@key}</codeph> (<xsl:sequence select="oa:type-label(oa:param-schema($h), '../schemas/', 0)"/>)<xsl:if test="normalize-space($h/j:string[@key='description'])">: {normalize-space($h/j:string[@key='description'])}</xsl:if></li>
                    </xsl:for-each>
                  </ul>
                </xsl:if>
              </stentry>
              <stentry>
                <xsl:choose>
                  <xsl:when test="$is-v2 and $r/j:map[@key='schema']">
                    <p><xsl:sequence select="oa:type-label($r/j:map[@key='schema'], '../schemas/', 0)"/></p>
                    <p><xsl:sequence select="oa:codeph-list(oa:v2-media($op, 'produces', 'application/json'))"/></p>
                  </xsl:when>
                  <xsl:when test="$r/j:map[@key='content']/j:map">
                    <xsl:for-each-group select="$r/j:map[@key='content']/j:map" group-by="string-join(oa:type-label(j:map[@key='schema'], '../schemas/', 0), '')">
                      <p>
                        <xsl:sequence select="if (j:map[@key='schema']) then oa:type-label(j:map[@key='schema'], '../schemas/', 0) else 'Unspecified'"/>
                      </p>
                      <p><xsl:sequence select="oa:codeph-list(current-group()/@key)"/></p>
                    </xsl:for-each-group>
                  </xsl:when>
                  <xsl:otherwise>None</xsl:otherwise>
                </xsl:choose>
              </stentry>
            </strow>
          </xsl:for-each>
        </simpletable>
        <!-- Property tables for response bodies defined inline (not as named schemas) -->
        <xsl:for-each select="j:map[@key='responses']/j:map">
          <xsl:variable name="r" select="oa:resolve(.)"/>
          <xsl:variable name="schema" select="if ($is-v2) then $r/j:map[@key='schema']
                                              else ($r/j:map[@key='content']/j:map/j:map[@key='schema'])[1]"/>
          <xsl:variable name="table" as="element()*">
            <xsl:call-template name="inline-properties">
              <xsl:with-param name="schema" select="$schema"/>
              <xsl:with-param name="from" select="'../schemas/'"/>
            </xsl:call-template>
          </xsl:variable>
          <xsl:if test="exists($table)">
            <p><b>{@key}{oa:status-text(@key)} response body</b><xsl:if test="$schema/j:map[@key='items'] and not($schema/j:map[@key='properties'])"> (array of objects with these properties)</xsl:if></p>
            <xsl:sequence select="$table"/>
          </xsl:if>
        </xsl:for-each>
      </section>
    </xsl:if>
  </xsl:template>

  <!-- First success response that has an example (explicit or from its schema) -->
  <xsl:template name="response-example">
    <xsl:variable name="candidates" as="element()*">
      <xsl:for-each select="j:map[@key='responses']/j:map[starts-with(@key, '2')]">
        <xsl:variable name="r" select="oa:resolve(.)"/>
        <xsl:choose>
          <xsl:when test="$is-v2">
            <xsl:variable name="ex" select="($r/j:map[@key='examples']/*[1], oa:schema-example($r/j:map[@key='schema'], 0))[1]"/>
            <xsl:if test="$ex">
              <oa:ex status="{@key}" media="{($r/j:map[@key='examples']/*[1]/@key, 'application/json')[1]}">
                <xsl:sequence select="$ex"/>
              </oa:ex>
            </xsl:if>
          </xsl:when>
          <xsl:otherwise>
            <xsl:for-each select="$r/j:map[@key='content']/j:map">
              <xsl:variable name="ex" select="oa:media-example(., j:map[@key='schema'])"/>
              <xsl:if test="$ex">
                <oa:ex status="{../../@key}" media="{@key}"><xsl:sequence select="$ex"/></oa:ex>
              </xsl:if>
            </xsl:for-each>
          </xsl:otherwise>
        </xsl:choose>
      </xsl:for-each>
    </xsl:variable>
    <xsl:for-each select="$candidates[1]">
      <example id="example-response">
        <title>Example response</title>
        <p><codeph>{@status}</codeph>{oa:status-text(@status)}, <codeph>{@media}</codeph></p>
        <codeblock outputclass="{oa:code-class(@media)}">{oa:example-text(*, @media)}</codeblock>
      </example>
    </xsl:for-each>
  </xsl:template>

  <!-- ===================================================================== -->
  <!-- Schema topic                                                          -->
  <!-- ===================================================================== -->

  <xsl:template name="write-schema">
    <xsl:variable name="name" select="string(@key)"/>
    <xsl:variable name="id" select="$schema-ids($name)"/>
    <xsl:variable name="s" select="oa:resolve(.)"/>
    <xsl:variable name="ref" select="$schema-prefix || oa:escape-pointer($name)"/>
    <xsl:result-document href="schemas/{$id}.dita" format="reference">
      <reference id="{$id}" xml:lang="{$lang}">
        <title>{$name}</title>
        <xsl:if test="$s/j:string[@key='title'] and $s/j:string[@key='title'] != $name">
          <shortdesc>{normalize-space($s/j:string[@key='title'])}</shortdesc>
        </xsl:if>
        <refbody>
          <section id="description">
            <xsl:sequence select="oa:md($s/j:string[@key='description'], 'body')"/>
            <p>Type: <xsl:sequence select="if ($s/j:array[@key='allOf'] and not($s/j:array[@key=('oneOf','anyOf')])) then 'object' else oa:type-label($s, '', 0)"/></p>
            <xsl:if test="$s/j:boolean[@key='deprecated'] = 'true'">
              <note type="attention">This schema is deprecated.</note>
            </xsl:if>
            <xsl:variable name="parents" select="$s/j:array[@key='allOf']/j:map[j:string[@key='$ref']]"/>
            <xsl:if test="$parents">
              <p>Includes all properties of: <xsl:for-each select="$parents">
                  <xsl:if test="position() gt 1">, </xsl:if>
                  <xsl:sequence select="oa:type-label(., '', 0)"/>
                </xsl:for-each></p>
            </xsl:if>
            <xsl:for-each select="$s/j:array[@key=('oneOf','anyOf')]">
              <p>{if (@key = 'oneOf') then 'Exactly one of:' else 'Any of:'}</p>
              <ul>
                <xsl:for-each select="j:map">
                  <li><xsl:sequence select="oa:type-label(., '', 0)"/>
                    <xsl:if test="not(j:string[@key='$ref']) and normalize-space(j:string[@key='description'])"> - {normalize-space(j:string[@key='description'])}</xsl:if></li>
                </xsl:for-each>
              </ul>
            </xsl:for-each>
            <xsl:for-each select="$s/j:map[@key='discriminator']">
              <p>Discriminator property: <codeph>{(j:string[@key='propertyName'], .)[1]}</codeph></p>
            </xsl:for-each>
            <xsl:if test="$is-v2 and $s/j:string[@key='discriminator']">
              <p>Discriminator property: <codeph>{$s/j:string[@key='discriminator']}</codeph></p>
            </xsl:if>
            <xsl:sequence select="oa:schema-notes($s)"/>
          </section>
          <xsl:if test="exists(oa:merged-properties($s))">
            <section id="properties">
              <title>Properties</title>
              <simpletable relcolwidth="2* 2* 1* 5*">
                <sthead><stentry>Property</stentry><stentry>Type</stentry><stentry>Required</stentry><stentry>Description</stentry></sthead>
                <xsl:call-template name="property-rows">
                  <xsl:with-param name="schema" select="$s"/>
                  <xsl:with-param name="prefix" select="''"/>
                  <xsl:with-param name="from" select="''"/>
                  <xsl:with-param name="depth" select="0"/>
                </xsl:call-template>
              </simpletable>
            </section>
          </xsl:if>
          <xsl:if test="$s/j:map[@key='additionalProperties'] and not($s/j:map[@key='properties'])">
            <section id="additional-properties">
              <title>Additional properties</title>
              <p>Values: <xsl:sequence select="oa:type-label($s/j:map[@key='additionalProperties'], '', 0)"/></p>
            </section>
          </xsl:if>
          <xsl:variable name="ex" select="oa:schema-example(., 0)"/>
          <xsl:if test="$ex">
            <example id="example">
              <title>Example</title>
              <codeblock outputclass="language-json">{oa:example-text($ex, 'application/json')}</codeblock>
            </example>
          </xsl:if>
        </refbody>
        <xsl:variable name="users" select="oa:users-of(key('refs', $ref, $doc), 0)"/>
        <xsl:if test="exists($users)">
          <related-links>
            <linklist>
              <title>Used by</title>
              <xsl:for-each select="$users">
                <xsl:sort select="starts-with(., 's:')"/>
                <xsl:choose>
                  <xsl:when test="starts-with(., 'o:')">
                    <link href="../operations/{substring(., 3)}.dita" type="reference"/>
                  </xsl:when>
                  <xsl:otherwise>
                    <link href="{substring(., 3)}.dita" type="reference"/>
                  </xsl:otherwise>
                </xsl:choose>
              </xsl:for-each>
            </linklist>
          </related-links>
        </xsl:if>
      </reference>
    </xsl:result-document>
  </xsl:template>

  <!-- Rows for each property; inline nested objects are flattened with dotted names -->
  <xsl:template name="property-rows">
    <xsl:param name="schema" as="element()"/>
    <xsl:param name="prefix" as="xs:string"/>
    <xsl:param name="from" as="xs:string"/>
    <xsl:param name="depth" as="xs:integer"/>
    <xsl:variable name="required" select="oa:merged-parts($schema, 0)/j:array[@key='required']/j:string/string()"/>
    <xsl:for-each select="oa:merged-properties($schema)">
      <xsl:variable name="p" select="."/>
      <xsl:variable name="pname" select="$prefix || @key"/>
      <strow>
        <stentry><codeph>{$pname}</codeph></stentry>
        <stentry><xsl:sequence select="oa:type-label(., $from, 0)"/></stentry>
        <stentry>{if (@key = $required) then 'Yes' else 'No'}</stentry>
        <stentry>
          <xsl:sequence select="oa:md(j:string[@key='description'], 'cell')"/>
          <xsl:sequence select="oa:schema-notes(.)"/>
        </stentry>
      </strow>
      <xsl:if test="$depth lt 4">
        <xsl:choose>
          <xsl:when test="not(j:string[@key='$ref']) and exists(oa:merged-properties(.))">
            <xsl:call-template name="property-rows">
              <xsl:with-param name="schema" select="."/>
              <xsl:with-param name="prefix" select="$pname || '.'"/>
              <xsl:with-param name="from" select="$from"/>
              <xsl:with-param name="depth" select="$depth + 1"/>
            </xsl:call-template>
          </xsl:when>
          <xsl:when test="j:map[@key='items'][not(j:string[@key='$ref'])] and exists(oa:merged-properties(j:map[@key='items']))">
            <xsl:call-template name="property-rows">
              <xsl:with-param name="schema" select="j:map[@key='items']"/>
              <xsl:with-param name="prefix" select="$pname || '[].'"/>
              <xsl:with-param name="from" select="$from"/>
              <xsl:with-param name="depth" select="$depth + 1"/>
            </xsl:call-template>
          </xsl:when>
        </xsl:choose>
      </xsl:if>
    </xsl:for-each>
  </xsl:template>

  <!-- ===================================================================== -->
  <!-- Schema helpers                                                        -->
  <!-- ===================================================================== -->

  <!-- The schema plus everything it pulls in through allOf (resolving $refs) -->
  <xsl:function name="oa:merged-parts" as="element()*">
    <xsl:param name="s" as="element()?"/>
    <xsl:param name="depth" as="xs:integer"/>
    <xsl:if test="$s and $depth lt 10">
      <xsl:variable name="r" select="oa:resolve($s)"/>
      <xsl:sequence select="$r"/>
      <xsl:sequence select="$r/j:array[@key='allOf']/j:map ! oa:merged-parts(., $depth + 1)"/>
    </xsl:if>
  </xsl:function>

  <xsl:function name="oa:merged-properties" as="element()*">
    <xsl:param name="s" as="element()?"/>
    <xsl:for-each-group select="oa:merged-parts($s, 0)/j:map[@key='properties']/j:map" group-by="string(@key)">
      <xsl:sequence select="current-group()[last()]"/>
    </xsl:for-each-group>
  </xsl:function>

  <!-- Human-readable type, with xrefs to schema topics. $from is the path to schemas/ -->
  <xsl:function name="oa:type-label" as="node()*">
    <xsl:param name="s" as="element()?"/>
    <xsl:param name="from" as="xs:string"/>
    <xsl:param name="depth" as="xs:integer"/>
    <xsl:variable name="ref" select="string($s/j:string[@key='$ref'])"/>
    <xsl:variable name="types" select="($s/j:string[@key='type'], $s/j:array[@key='type']/j:string)/string()"/>
    <xsl:variable name="nullable" select="$s/j:boolean[@key='nullable'] = 'true' or $s/j:boolean[@key='x-nullable'] = 'true'"/>
    <xsl:choose>
      <xsl:when test="empty($s)">any</xsl:when>
      <xsl:when test="$depth gt 6">object</xsl:when>
      <xsl:when test="$ref != ''">
        <xsl:variable name="name" select="oa:schema-name($ref)"/>
        <xsl:choose>
          <xsl:when test="$name != '' and $write-schemas">
            <xref href="{$from}{$schema-ids($name)}.dita" type="reference">{$name}</xref>
          </xsl:when>
          <xsl:when test="$name != ''">{$name}</xsl:when>
          <xsl:when test="exists(oa:pointer($ref))">
            <xsl:sequence select="oa:type-label(oa:pointer($ref), $from, $depth + 1)"/>
          </xsl:when>
          <xsl:otherwise><codeph>{$ref}</codeph></xsl:otherwise>
        </xsl:choose>
      </xsl:when>
      <xsl:when test="$s/j:array[@key=('oneOf','anyOf')]/j:map">
        <xsl:for-each select="$s/j:array[@key=('oneOf','anyOf')]/j:map">
          <xsl:if test="position() gt 1"> | </xsl:if>
          <xsl:sequence select="oa:type-label(., $from, $depth + 1)"/>
        </xsl:for-each>
      </xsl:when>
      <xsl:when test="count($s/j:array[@key='allOf']/j:map) eq 1 and not($s/j:map[@key='properties'])">
        <xsl:sequence select="oa:type-label($s/j:array[@key='allOf']/j:map, $from, $depth + 1)"/>
      </xsl:when>
      <xsl:when test="$s/j:array[@key='allOf']/j:map[j:string[@key='$ref']]">
        <xsl:for-each select="$s/j:array[@key='allOf']/j:map[j:string[@key='$ref']]">
          <xsl:if test="position() gt 1"> + </xsl:if>
          <xsl:sequence select="oa:type-label(., $from, $depth + 1)"/>
        </xsl:for-each>
        <xsl:if test="$s/j:array[@key='allOf']/j:map[not(j:string[@key='$ref'])] or $s/j:map[@key='properties']"> (extended)</xsl:if>
      </xsl:when>
      <xsl:when test="$s/j:array[@key='allOf']/j:map">object</xsl:when>
      <xsl:when test="$types = 'array' or $s/j:map[@key='items']">
        <xsl:text>array of </xsl:text>
        <xsl:sequence select="oa:type-label($s/j:map[@key='items'], $from, $depth + 1)"/>
        <xsl:if test="$nullable or count($types) gt 1"> | {string-join(($types[. != 'array'], if ($nullable) then 'null' else ()), ' | ')}</xsl:if>
      </xsl:when>
      <xsl:when test="$s/j:map[@key='additionalProperties'] and not($s/j:map[@key='properties'])">
        <xsl:text>map of </xsl:text>
        <xsl:sequence select="oa:type-label($s/j:map[@key='additionalProperties'], $from, $depth + 1)"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:variable name="base" select="if (exists($types)) then string-join($types, ' | ')
                                          else if ($s/j:map[@key='properties']) then 'object'
                                          else if ($s/j:array[@key='enum']) then 'enum'
                                          else 'any'"/>
        <xsl:variable name="extra" select="($s/j:string[@key='format']/string(), if ($nullable) then 'nullable' else ())"/>
        <xsl:value-of select="$base || (if (exists($extra)) then ' (' || string-join($extra, ', ') || ')' else '')"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:function>

  <!-- Notes on enum, default, constraints, read/write-only -->
  <xsl:function name="oa:schema-notes" as="element()*">
    <xsl:param name="s" as="element()?"/>
    <xsl:if test="$s and not($s/j:string[@key='$ref'])">
      <xsl:if test="$s/j:boolean[@key='deprecated'] = 'true' and $s/j:string[@key='type']"><p><b>Deprecated.</b></p></xsl:if>
      <xsl:if test="$s/j:boolean[@key='readOnly'] = 'true'"><p>Read-only.</p></xsl:if>
      <xsl:if test="$s/j:boolean[@key='writeOnly'] = 'true'"><p>Write-only.</p></xsl:if>
      <xsl:variable name="enum" select="($s/j:array[@key='enum'], $s/j:map[@key='items'][not(j:string[@key='$ref'])]/j:array[@key='enum'])[1]"/>
      <xsl:if test="$enum/*">
        <p>Allowed values: <xsl:sequence select="oa:codeph-list($enum/* ! oa:scalar-text(.))"/></p>
      </xsl:if>
      <xsl:if test="exists($s/*[@key='const'])">
        <p>Value: <codeph>{oa:scalar-text($s/*[@key='const'])}</codeph></p>
      </xsl:if>
      <xsl:if test="exists($s/*[@key='default'])">
        <p>Default: <codeph>{oa:scalar-text($s/*[@key='default'])}</codeph></p>
      </xsl:if>
      <xsl:variable name="c" as="xs:string*">
        <xsl:for-each select="$s/*[@key=('minimum','maximum','exclusiveMinimum','exclusiveMaximum','minLength','maxLength','minItems','maxItems','multipleOf','uniqueItems','minProperties','maxProperties')]">
          <xsl:choose>
            <xsl:when test="self::j:boolean and @key = 'uniqueItems'"><xsl:if test=". = 'true'">items must be unique</xsl:if></xsl:when>
            <xsl:when test="self::j:boolean"><xsl:if test=". = 'true'">{if (@key = 'exclusiveMinimum') then 'minimum is exclusive' else 'maximum is exclusive'}</xsl:if></xsl:when>
            <xsl:otherwise>{oa:constraint-label(@key)} {.}</xsl:otherwise>
          </xsl:choose>
        </xsl:for-each>
      </xsl:variable>
      <xsl:if test="exists($c[normalize-space()]) or $s/j:string[@key='pattern']">
        <p>Constraints: {string-join($c[normalize-space()], '; ')}<xsl:if test="$s/j:string[@key='pattern']"><xsl:if test="exists($c[normalize-space()])">; </xsl:if>pattern <codeph>{$s/j:string[@key='pattern']}</codeph></xsl:if></p>
      </xsl:if>
      <xsl:if test="$s/*[@key='example'][self::j:string or self::j:number or self::j:boolean]">
        <p>Example: <codeph>{$s/*[@key='example']}</codeph></p>
      </xsl:if>
    </xsl:if>
  </xsl:function>

  <xsl:function name="oa:constraint-label" as="xs:string">
    <xsl:param name="k" as="xs:string"/>
    <xsl:sequence select="map{
      'minimum':'minimum', 'maximum':'maximum', 'exclusiveMinimum':'greater than',
      'exclusiveMaximum':'less than', 'minLength':'minimum length', 'maxLength':'maximum length',
      'minItems':'minimum items', 'maxItems':'maximum items', 'multipleOf':'multiple of',
      'minProperties':'minimum properties', 'maxProperties':'maximum properties'}($k)"/>
  </xsl:function>

  <!-- Schema name from a $ref, or '' if it doesn't point at a named schema -->
  <xsl:function name="oa:schema-name" as="xs:string">
    <xsl:param name="ref" as="xs:string"/>
    <xsl:variable name="rest" select="if (starts-with($ref, $schema-prefix)) then substring-after($ref, $schema-prefix) else ''"/>
    <xsl:variable name="name" select="oa:unescape-pointer($rest)"/>
    <xsl:sequence select="if ($rest != '' and not(contains($rest, '/')) and exists($schema-ids($name))) then $name else ''"/>
  </xsl:function>

  <!-- Named schemas an operation refers to (directly, or through shared components) -->
  <xsl:function name="oa:schemas-used-by-op" as="xs:string*">
    <xsl:param name="op" as="element()"/>
    <xsl:variable name="direct" select="($op, $op/../j:array[@key='parameters'])//j:string[@key='$ref']/string()"/>
    <xsl:variable name="all" select="oa:expand-refs($direct, 0)"/>
    <xsl:sequence select="distinct-values($all ! oa:schema-name(.))[. != '']"/>
  </xsl:function>

  <!-- Follow refs to non-schema components (responses, parameters, requestBodies...) -->
  <xsl:function name="oa:expand-refs" as="xs:string*">
    <xsl:param name="refs" as="xs:string*"/>
    <xsl:param name="depth" as="xs:integer"/>
    <xsl:sequence select="$refs"/>
    <xsl:if test="$depth lt 3">
      <xsl:variable name="indirect" select="$refs[not(starts-with(., $schema-prefix)) and starts-with(., '#/')]"/>
      <xsl:if test="exists($indirect)">
        <xsl:sequence select="oa:expand-refs(distinct-values($indirect ! oa:pointer(.)//j:string[@key='$ref']/string()), $depth + 1)"/>
      </xsl:if>
    </xsl:if>
  </xsl:function>

  <!-- For "Used by" links: 'o:<op id>' or 's:<schema id>' for each place that uses $refs -->
  <xsl:function name="oa:users-of" as="xs:string*">
    <xsl:param name="refs" as="element()*"/>
    <xsl:param name="depth" as="xs:integer"/>
    <xsl:variable name="result" as="xs:string*">
      <xsl:for-each select="$refs">
        <xsl:variable name="op" select="ancestor::j:map[@key = $methods][../../@key = ('paths','webhooks')][1]"/>
        <xsl:variable name="path-item" select="ancestor::j:map[../@key = ('paths','webhooks')][1]"/>
        <xsl:variable name="schema" select="ancestor::j:map[parent::* is $schemas][1]"/>
        <xsl:variable name="component" select="ancestor::j:map[../../@key = 'components' or (../@key = ('parameters','responses') and not(../..[parent::*]))][1]"/>
        <xsl:choose>
          <xsl:when test="$op">{'o:' || oa:op-id($op)}</xsl:when>
          <xsl:when test="$path-item">
            <xsl:sequence select="$path-item/j:map[@key = $methods] ! ('o:' || oa:op-id(.))"/>
          </xsl:when>
          <xsl:when test="$schema">{'s:' || $schema-ids(string($schema/@key))}</xsl:when>
          <xsl:when test="$component and $depth lt 3">
            <xsl:variable name="pointer" select="if ($component/../../@key = 'components')
              then '#/components/' || $component/../@key || '/' || oa:escape-pointer($component/@key)
              else '#/' || $component/../@key || '/' || oa:escape-pointer($component/@key)"/>
            <xsl:sequence select="oa:users-of(key('refs', $pointer, $doc), $depth + 1)"/>
          </xsl:when>
        </xsl:choose>
      </xsl:for-each>
    </xsl:variable>
    <xsl:sequence select="distinct-values($result)"/>
  </xsl:function>

  <!-- ===================================================================== -->
  <!-- Operation helpers                                                     -->
  <!-- ===================================================================== -->

  <xsl:function name="oa:op-base-id" as="xs:string">
    <xsl:param name="op" as="element()"/>
    <xsl:sequence select="if (normalize-space($op/j:string[@key='operationId']))
                          then oa:ncname($op/j:string[@key='operationId'])
                          else oa:ncname($op/@key || '_' || $op/../@key)"/>
  </xsl:function>

  <xsl:function name="oa:op-id" as="xs:string">
    <xsl:param name="op" as="element()"/>
    <xsl:sequence select="$op-ids(generate-id($op))"/>
  </xsl:function>

  <xsl:function name="oa:op-title" as="xs:string">
    <xsl:param name="op" as="element()"/>
    <xsl:variable name="summary" select="normalize-space($op/j:string[@key='summary'])"/>
    <xsl:sequence select="if ($summary) then replace($summary, '\.$', '')
                          else if (oa:is-webhook($op)) then $op/../@key || ' webhook'
                          else upper-case($op/@key) || ' ' || $op/../@key"/>
  </xsl:function>

  <!-- Path-level parameters merged with operation-level ones (operation wins) -->
  <xsl:function name="oa:op-parameters" as="element()*">
    <xsl:param name="op" as="element()"/>
    <xsl:variable name="all" select="($op/../j:array[@key='parameters']/j:map, $op/j:array[@key='parameters']/j:map) ! oa:resolve(.)"/>
    <xsl:for-each-group select="$all" group-by="j:string[@key='name'] || '|' || j:string[@key='in']">
      <xsl:sequence select="current-group()[last()]"/>
    </xsl:for-each-group>
  </xsl:function>

  <!-- The schema-like map for a parameter or header -->
  <xsl:function name="oa:param-schema" as="element()?">
    <xsl:param name="p" as="element()?"/>
    <xsl:sequence select="if ($p/j:map[@key='schema']) then $p/j:map[@key='schema']
                          else if ($p/j:map[@key='content']/j:map/j:map[@key='schema']) then ($p/j:map[@key='content']/j:map/j:map[@key='schema'])[1]
                          else if ($p/*[@key='type']) then $p
                          else ()"/>
  </xsl:function>

  <xsl:function name="oa:v2-media" as="xs:string*">
    <xsl:param name="op" as="element()"/>
    <xsl:param name="which" as="xs:string"/>
    <xsl:param name="fallback" as="xs:string"/>
    <xsl:variable name="v" select="($op/j:array[@key=$which], $root/j:array[@key=$which])[1]/j:string/string()"/>
    <xsl:sequence select="if (exists($v)) then $v else $fallback"/>
  </xsl:function>

  <xsl:function name="oa:server-url" as="xs:string">
    <xsl:param name="context" as="element()"/>
    <xsl:choose>
      <xsl:when test="$is-v2">
        <xsl:sequence select="if ($root/j:string[@key='host'])
          then (($root/j:array[@key='schemes']/j:string)[1], 'https')[1] || '://' || $root/j:string[@key='host'] || replace(string($root/j:string[@key='basePath']), '/$', '')
          else replace(string($root/j:string[@key='basePath']), '/$', '')"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:variable name="srv" select="($context/j:array[@key='servers']/j:map)[1]"/>
        <xsl:variable name="url" select="string($srv/j:string[@key='url'])"/>
        <xsl:variable name="expanded" as="xs:string">
          <xsl:iterate select="$srv/j:map[@key='variables']/j:map">
            <xsl:param name="u" select="$url"/>
            <xsl:on-completion select="$u"/>
            <xsl:next-iteration>
              <xsl:with-param name="u" select="replace($u, '\{' || oa:regex-escape(@key) || '\}', replace(string(*[@key='default']), '\$', '\\\$'))"/>
            </xsl:next-iteration>
          </xsl:iterate>
        </xsl:variable>
        <xsl:sequence select="replace($expanded, '/$', '')"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:function>

  <xsl:function name="oa:op-server" as="xs:string">
    <xsl:param name="op" as="element()"/>
    <xsl:sequence select="if (not($is-v2) and $op/j:array[@key='servers']/j:map) then oa:server-url($op)
                          else if (not($is-v2) and $op/../j:array[@key='servers']/j:map) then oa:server-url($op/..)
                          else $default-server"/>
  </xsl:function>

  <xsl:function name="oa:curl" as="xs:string">
    <xsl:param name="op" as="element()"/>
    <xsl:param name="params" as="element()*"/>
    <xsl:param name="server" as="xs:string"/>
    <xsl:variable name="query" select="$params[j:string[@key='in'] = 'query'][j:boolean[@key='required'] = 'true']"/>
    <xsl:variable name="url" select="$server || $op/../@key ||
      (if ($query) then '?' || string-join($query ! (j:string[@key='name'] || '=' || oa:sample-value(.)), '&amp;') else '')"/>
    <xsl:variable name="headers" as="xs:string*">
      <xsl:for-each select="$params[j:string[@key='in'] = 'header'][j:boolean[@key='required'] = 'true']">
        <xsl:sequence select="j:string[@key='name'] || ': ' || oa:sample-value(.)"/>
      </xsl:for-each>
      <xsl:sequence select="oa:auth-headers($op)"/>
    </xsl:variable>
    <xsl:variable name="rb" select="if ($is-v2) then () else oa:resolve($op/j:map[@key='requestBody'])"/>
    <xsl:variable name="media" select="if ($rb) then string(($rb/j:map[@key='content']/j:map/@key)[1])
      else if ($is-v2 and $params[j:string[@key='in'] = 'body']) then oa:v2-media($op, 'consumes', 'application/json')[1]
      else ''"/>
    <xsl:variable name="body-example" select="
      if ($rb) then oa:media-example(($rb/j:map[@key='content']/j:map)[1], ($rb/j:map[@key='content']/j:map)[1]/j:map[@key='schema'])
      else if ($is-v2) then oa:schema-example($params[j:string[@key='in'] = 'body'][1]/j:map[@key='schema'], 0)
      else ()"/>
    <xsl:variable name="lines" as="xs:string*" select="
      'curl -X ' || upper-case($op/@key) || ' &quot;' || $url || '&quot;',
      $headers ! ('  -H &quot;' || . || '&quot;'),
      (if ($media) then '  -H &quot;Content-Type: ' || $media || '&quot;' else ()),
      (if ($body-example) then '  -d ''' || replace(oa:example-text($body-example, $media), '''', '''\\''''') || ''''
       else if ($media) then '  -d @request.json' else ())"/>
    <xsl:sequence select="string-join($lines, ' \' || $NL)"/>
  </xsl:function>

  <xsl:function name="oa:auth-headers" as="xs:string*">
    <xsl:param name="op" as="element()"/>
    <xsl:variable name="sec" select="if ($op/j:array[@key='security']) then $op/j:array[@key='security'] else $root/j:array[@key='security']"/>
    <xsl:variable name="first" select="($sec/j:map[*])[1]"/>
    <xsl:for-each select="$first/j:array">
      <xsl:variable name="s" select="oa:resolve($security-schemes/j:map[@key = current()/@key])"/>
      <xsl:variable name="type" select="string($s/j:string[@key='type'])"/>
      <xsl:choose>
        <xsl:when test="$type = 'apiKey' and $s/j:string[@key='in'] = 'header'">{$s/j:string[@key='name']}: $API_KEY</xsl:when>
        <xsl:when test="$type = ('oauth2','openIdConnect') or ($type = 'http' and lower-case($s/j:string[@key='scheme']) = 'bearer')">Authorization: Bearer $TOKEN</xsl:when>
        <xsl:when test="$type = 'basic' or ($type = 'http' and lower-case($s/j:string[@key='scheme']) = 'basic')">Authorization: Basic $CREDENTIALS</xsl:when>
      </xsl:choose>
    </xsl:for-each>
  </xsl:function>

  <xsl:function name="oa:sample-value" as="xs:string">
    <xsl:param name="p" as="element()"/>
    <xsl:variable name="s" select="oa:param-schema($p)"/>
    <xsl:sequence select="(
      $p/*[@key='example'][not(self::j:map or self::j:array)]/string(),
      $s/*[@key='example'][not(self::j:map or self::j:array)]/string(),
      $s/*[@key='default'][not(self::j:map or self::j:array)]/string(),
      $s/j:array[@key='enum']/*[1]/string(),
      upper-case(replace($p/j:string[@key='name'], '[^A-Za-z0-9]+', '_')))[1]"/>
  </xsl:function>

  <!-- ===================================================================== -->
  <!-- Examples                                                              -->
  <!-- ===================================================================== -->

  <!-- Example for an OpenAPI 3 media type object: example, examples, or schema example -->
  <xsl:function name="oa:media-example" as="element()?">
    <xsl:param name="media" as="element()?"/>
    <xsl:param name="schema" as="element()?"/>
    <xsl:sequence select="(
      $media/*[@key='example'],
      ($media/j:map[@key='examples']/j:map ! oa:resolve(.))[1]/*[@key='value'],
      oa:schema-example($schema, 0))[1]"/>
  </xsl:function>

  <!-- Example from a schema: its own example, or a sample built from its structure -->
  <xsl:function name="oa:schema-example" as="element()?">
    <xsl:param name="s" as="element()?"/>
    <xsl:param name="depth" as="xs:integer"/>
    <xsl:variable name="r" select="oa:resolve($s)"/>
    <xsl:variable name="type" select="string(($r/j:string[@key='type'], $r/j:array[@key='type']/j:string[. != 'null'])[1])"/>
    <xsl:choose>
      <xsl:when test="empty($r) or $depth gt 6"/>
      <xsl:when test="$r/*[@key='example']">
        <xsl:sequence select="$r/*[@key='example']"/>
      </xsl:when>
      <xsl:when test="$r/j:array[@key='examples']/*">
        <xsl:sequence select="$r/j:array[@key='examples']/*[1]"/>
      </xsl:when>
      <xsl:when test="exists($r/*[@key='default'])">
        <xsl:sequence select="$r/*[@key='default']"/>
      </xsl:when>
      <xsl:when test="$r/j:array[@key='enum']/*">
        <xsl:sequence select="$r/j:array[@key='enum']/*[1]"/>
      </xsl:when>
      <xsl:when test="exists($r/*[@key='const'])">
        <xsl:sequence select="$r/*[@key='const']"/>
      </xsl:when>
      <xsl:when test="$r/j:array[@key=('oneOf','anyOf')]/j:map">
        <xsl:sequence select="oa:schema-example(($r/j:array[@key=('oneOf','anyOf')]/j:map)[1], $depth + 1)"/>
      </xsl:when>
      <xsl:when test="exists(oa:merged-properties($r))">
        <j:map>
          <xsl:for-each select="oa:merged-properties($r)">
            <xsl:variable name="ex" select="oa:schema-example(., $depth + 1)"/>
            <xsl:if test="$ex">
              <xsl:sequence select="oa:with-key($ex, @key)"/>
            </xsl:if>
          </xsl:for-each>
        </j:map>
      </xsl:when>
      <xsl:when test="$type = 'array' or $r/j:map[@key='items']">
        <xsl:variable name="item" select="oa:schema-example($r/j:map[@key='items'], $depth + 1)"/>
        <j:array><xsl:sequence select="$item ! oa:with-key(., ())"/></j:array>
      </xsl:when>
      <xsl:when test="$r/j:map[@key='additionalProperties']">
        <xsl:variable name="v" select="oa:schema-example($r/j:map[@key='additionalProperties'], $depth + 1)"/>
        <j:map><xsl:sequence select="$v ! oa:with-key(., 'key')"/></j:map>
      </xsl:when>
      <xsl:when test="$type = 'object'"><j:map/></xsl:when>
      <xsl:when test="$type = ('integer','number')"><j:number>{($r/*[@key='minimum'], 0)[1]}</j:number></xsl:when>
      <xsl:when test="$type = 'boolean'"><j:boolean>true</j:boolean></xsl:when>
      <xsl:when test="$type = 'string'">
        <xsl:variable name="format" select="string($r/j:string[@key='format'])"/>
        <j:string><xsl:value-of select="(map{
          'date':'2024-01-31', 'date-time':'2024-01-31T09:30:00Z', 'time':'09:30:00',
          'uuid':'3fa85f64-5717-4562-b3fc-2c963f66afa6', 'email':'user@example.com',
          'uri':'https://example.com', 'url':'https://example.com', 'hostname':'example.com',
          'ipv4':'192.0.2.1', 'ipv6':'2001:db8::1', 'byte':'U3dhZ2dlcg==', 'password':'********'
          }($format), 'string')[1]"/></j:string>
      </xsl:when>
    </xsl:choose>
  </xsl:function>

  <!-- Copy of a json-to-xml node with a different (or no) key -->
  <xsl:function name="oa:with-key" as="element()">
    <xsl:param name="n" as="element()"/>
    <xsl:param name="key" as="xs:string?"/>
    <xsl:element name="{local-name($n)}" namespace="http://www.w3.org/2005/xpath-functions">
      <xsl:if test="exists($key)"><xsl:attribute name="key" select="$key"/></xsl:if>
      <xsl:sequence select="$n/(@* except @key), $n/node()"/>
    </xsl:element>
  </xsl:function>

  <xsl:function name="oa:example-text" as="xs:string">
    <xsl:param name="ex" as="element()"/>
    <xsl:param name="media" as="xs:string"/>
    <xsl:sequence select="if ($ex/self::j:string and not(contains($media, 'json'))) then string($ex) else oa:json($ex, '')"/>
  </xsl:function>

  <xsl:function name="oa:code-class" as="xs:string">
    <xsl:param name="media" as="xs:string"/>
    <xsl:sequence select="if (contains($media, 'json')) then 'language-json'
                          else if (contains($media, 'xml')) then 'language-xml'
                          else if (contains($media, 'yaml')) then 'language-yaml'
                          else 'language-text'"/>
  </xsl:function>

  <!-- Pretty-printed JSON from the json-to-xml representation (keeps key order) -->
  <xsl:function name="oa:json" as="xs:string">
    <xsl:param name="n" as="element()"/>
    <xsl:param name="indent" as="xs:string"/>
    <xsl:variable name="in2" select="$indent || '  '"/>
    <xsl:choose>
      <xsl:when test="$n/self::j:map">
        <xsl:sequence select="if (empty($n/*)) then '{}' else
          '{' || $NL || string-join($n/* ! ($in2 || oa:json-string(@key) || ': ' || oa:json(., $in2)), ',' || $NL) || $NL || $indent || '}'"/>
      </xsl:when>
      <xsl:when test="$n/self::j:array">
        <xsl:sequence select="if (empty($n/*)) then '[]'
          else if (every $c in $n/* satisfies not($c/self::j:map or $c/self::j:array)) then
            '[' || string-join($n/* ! oa:json(., $in2), ', ') || ']'
          else '[' || $NL || string-join($n/* ! ($in2 || oa:json(., $in2)), ',' || $NL) || $NL || $indent || ']'"/>
      </xsl:when>
      <xsl:when test="$n/self::j:string"><xsl:sequence select="oa:json-string($n)"/></xsl:when>
      <xsl:when test="$n/self::j:null"><xsl:sequence select="'null'"/></xsl:when>
      <xsl:otherwise><xsl:sequence select="string($n)"/></xsl:otherwise>
    </xsl:choose>
  </xsl:function>

  <xsl:function name="oa:json-string" as="xs:string">
    <xsl:param name="s" as="xs:string"/>
    <xsl:variable name="e" select="replace(replace(replace(replace(replace($s, '\\', '\\\\'), '&quot;', '\\&quot;'), '&#10;', '\\n'), '&#13;', '\\r'), '&#9;', '\\t')"/>
    <xsl:sequence select="'&quot;' || $e || '&quot;'"/>
  </xsl:function>

  <xsl:function name="oa:scalar-text" as="xs:string">
    <xsl:param name="n" as="element()"/>
    <xsl:sequence select="if ($n/self::j:map or $n/self::j:array) then replace(oa:json($n, ''), '\s*\n\s*', ' ')
                          else if ($n/self::j:null) then 'null' else string($n)"/>
  </xsl:function>

  <!-- ===================================================================== -->
  <!-- $ref resolution                                                       -->
  <!-- ===================================================================== -->

  <xsl:function name="oa:resolve" as="element()?">
    <xsl:param name="n" as="element()?"/>
    <xsl:sequence select="oa:resolve($n, 0)"/>
  </xsl:function>

  <xsl:function name="oa:resolve" as="element()?">
    <xsl:param name="n" as="element()?"/>
    <xsl:param name="depth" as="xs:integer"/>
    <xsl:variable name="ref" select="string($n/j:string[@key='$ref'])"/>
    <xsl:sequence select="if ($ref = '' or $depth gt 20) then $n
                          else if (exists(oa:pointer($ref))) then oa:resolve(oa:pointer($ref), $depth + 1)
                          else $n"/>
  </xsl:function>

  <!-- Local JSON pointer (#/a/b/0) to node; external refs return empty -->
  <xsl:function name="oa:pointer" as="element()?" cache="yes">
    <xsl:param name="ref" as="xs:string"/>
    <xsl:if test="starts-with($ref, '#/')">
      <xsl:variable name="tokens" select="tokenize(substring($ref, 3), '/') ! oa:unescape-pointer(.)"/>
      <xsl:sequence select="fold-left($tokens, $root, function($node, $t) {
        if ($node/self::j:array and $t castable as xs:integer) then $node/*[xs:integer($t) + 1]
        else $node/*[@key = $t] })[1]"/>
    </xsl:if>
  </xsl:function>

  <xsl:function name="oa:unescape-pointer" as="xs:string">
    <xsl:param name="s" as="xs:string"/>
    <xsl:variable name="decoded" select="if (contains($s, '%')) then oa:percent-decode($s) else $s"/>
    <xsl:sequence select="replace(replace($decoded, '~1', '/'), '~0', '~')"/>
  </xsl:function>

  <xsl:function name="oa:escape-pointer" as="xs:string">
    <xsl:param name="s" as="xs:string"/>
    <xsl:sequence select="replace(replace($s, '~', '~0'), '/', '~1')"/>
  </xsl:function>

  <xsl:function name="oa:percent-decode" as="xs:string">
    <xsl:param name="s" as="xs:string"/>
    <xsl:variable name="parts" as="xs:string*">
      <xsl:analyze-string select="$s" regex="(%[0-9A-Fa-f]{{2}})+">
        <xsl:matching-substring>
          <xsl:variable name="bytes" select="tokenize(substring(., 2), '%') ! oa:hex(.)"/>
          <xsl:sequence select="if (every $b in $bytes satisfies $b lt 128) then codepoints-to-string($bytes) else ."/>
        </xsl:matching-substring>
        <xsl:non-matching-substring><xsl:sequence select="."/></xsl:non-matching-substring>
      </xsl:analyze-string>
    </xsl:variable>
    <xsl:sequence select="string-join($parts)"/>
  </xsl:function>

  <xsl:function name="oa:hex" as="xs:integer">
    <xsl:param name="h" as="xs:string"/>
    <xsl:sequence select="fold-left(string-to-codepoints(upper-case($h)), 0, function($a, $c) {
      $a * 16 + (if ($c ge 65) then $c - 55 else $c - 48) })"/>
  </xsl:function>

  <!-- ===================================================================== -->
  <!-- Markdown                                                              -->
  <!-- ===================================================================== -->

  <!-- Markdown text to DITA block content. $context is 'body' or 'cell' -->
  <xsl:function name="oa:md" as="node()*">
    <xsl:param name="text" as="xs:string?"/>
    <xsl:param name="context" as="xs:string"/>
    <xsl:if test="normalize-space($text)">
      <xsl:variable name="parsed" as="document-node()?">
        <xsl:sequence use-when="function-available('md:markdown', 1)" select="md:markdown('# x' || $NL || $NL || $text)"/>
      </xsl:variable>
      <xsl:choose>
        <xsl:when test="$parsed//*[contains(@class, ' topic/body ')]">
          <xsl:for-each select="$parsed//*[contains(@class, ' topic/topic ')]">
            <xsl:if test="position() gt 1">
              <p><b>{normalize-space(*[contains(@class, ' topic/title ')])}</b></p>
            </xsl:if>
            <xsl:apply-templates select="*[contains(@class, ' topic/shortdesc ')], *[contains(@class, ' topic/body ')]/node()" mode="md">
              <xsl:with-param name="context" select="$context" tunnel="yes"/>
            </xsl:apply-templates>
          </xsl:for-each>
        </xsl:when>
        <xsl:otherwise>
          <xsl:sequence select="oa:md-basic($text)"/>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:if>
  </xsl:function>

  <xsl:template match="*" mode="md">
    <xsl:element name="{local-name()}">
      <xsl:apply-templates select="@*" mode="md"/>
      <xsl:apply-templates mode="md"/>
    </xsl:element>
  </xsl:template>

  <xsl:template match="@*" mode="md">
    <xsl:attribute name="{local-name()}" select="."/>
  </xsl:template>
  <xsl:template match="@class | @specializations | @domains | @*[local-name() = 'DITAArchVersion'] | @xml:space" mode="md"/>
  <xsl:template match="@xml:lang" mode="md"><xsl:copy/></xsl:template>
  <xsl:template match="*[contains(@class, ' topic/shortdesc ')]" mode="md">
    <p><xsl:apply-templates mode="md"/></p>
  </xsl:template>

  <!-- Only keep links to absolute URLs; relative links can't be resolved in the output -->
  <xsl:template match="*[contains(@class, ' topic/xref ')][not(matches(@href, '^[a-zA-Z][a-zA-Z0-9+.\-]*:'))]" mode="md">
    <xsl:apply-templates mode="md"/>
  </xsl:template>
  <xsl:template match="*[contains(@class, ' topic/xref ')][matches(@href, '^[a-zA-Z][a-zA-Z0-9+.\-]*:')]" mode="md">
    <xref href="{@href}" scope="external" format="{if (starts-with(@href, 'mailto:')) then 'email' else 'html'}">
      <xsl:apply-templates mode="md"/>
    </xref>
  </xsl:template>
  <xsl:template match="*[contains(@class, ' topic/image ')]" mode="md">
    <xsl:choose>
      <xsl:when test="matches(@href, '^https?:')">
        <image href="{@href}" scope="external">
          <xsl:apply-templates select="@placement" mode="md"/>
          <xsl:apply-templates mode="md"/>
        </image>
      </xsl:when>
      <xsl:otherwise>
        <xsl:value-of select="normalize-space(.)"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  <!-- Tables and sections can't go inside table cells -->
  <xsl:template match="*[contains(@class, ' topic/table ') or contains(@class, ' topic/simpletable ')]" mode="md">
    <xsl:param name="context" tunnel="yes"/>
    <xsl:choose>
      <xsl:when test="$context = 'cell'">
        <xsl:for-each select=".//*[contains(@class, ' topic/row ') or contains(@class, ' topic/strow ') or contains(@class, ' topic/sthead ')]">
          <p>{string-join(*/normalize-space(), ' | ')}</p>
        </xsl:for-each>
      </xsl:when>
      <xsl:otherwise><xsl:next-match/></xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  <xsl:template match="*[contains(@class, ' topic/section ')]" mode="md">
    <xsl:apply-templates mode="md"/>
  </xsl:template>
  <xsl:template match="*[contains(@class, ' topic/section ')]/*[contains(@class, ' topic/title ')]" mode="md">
    <p><b><xsl:apply-templates mode="md"/></b></p>
  </xsl:template>
  <!-- Raw HTML that the Markdown parser couldn't map: keep the text -->
  <xsl:template match="*[contains(@class, ' topic/foreign ') or contains(@class, ' topic/unknown ') or contains(@class, ' topic/required-cleanup ')]" mode="md">
    <xsl:value-of select="."/>
  </xsl:template>

  <!-- Fallback when no Markdown parser is available: paragraphs, lists, code -->
  <xsl:function name="oa:md-basic" as="element()*">
    <xsl:param name="text" as="xs:string"/>
    <xsl:for-each select="tokenize(replace($text, '\r', ''), '\n[ \t]*\n')[normalize-space()]">
      <xsl:variable name="lines" select="tokenize(., '\n')[normalize-space()]"/>
      <xsl:choose>
        <xsl:when test="matches(., '^\s*```')">
          <codeblock>{replace(replace(., '^\s*```[^\n]*\n?', ''), '\n?```\s*$', '')}</codeblock>
        </xsl:when>
        <xsl:when test="every $l in $lines satisfies matches($l, '^\s*([-*+]|\d+\.)\s')">
          <xsl:element name="{if (matches($lines[1], '^\s*\d')) then 'ol' else 'ul'}">
            <xsl:for-each select="$lines">
              <li><xsl:sequence select="oa:md-inline(replace(., '^\s*([-*+]|\d+\.)\s+', ''))"/></li>
            </xsl:for-each>
          </xsl:element>
        </xsl:when>
        <xsl:otherwise>
          <p><xsl:sequence select="oa:md-inline(replace(normalize-space(.), '^#+\s*', ''))"/></p>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:for-each>
  </xsl:function>

  <xsl:function name="oa:md-inline" as="node()*">
    <xsl:param name="s" as="xs:string"/>
    <xsl:analyze-string select="$s" regex="`([^`]+)`|\*\*([^*]+)\*\*|\[([^\]]+)\]\((https?://[^)\s]+)\)">
      <xsl:matching-substring>
        <xsl:choose>
          <xsl:when test="regex-group(1)"><codeph>{regex-group(1)}</codeph></xsl:when>
          <xsl:when test="regex-group(2)"><b>{regex-group(2)}</b></xsl:when>
          <xsl:otherwise><xref href="{regex-group(4)}" scope="external" format="html">{regex-group(3)}</xref></xsl:otherwise>
        </xsl:choose>
      </xsl:matching-substring>
      <xsl:non-matching-substring><xsl:value-of select="."/></xsl:non-matching-substring>
    </xsl:analyze-string>
  </xsl:function>

  <!-- ===================================================================== -->
  <!-- Small utilities                                                       -->
  <!-- ===================================================================== -->

  <xsl:function name="oa:api-title" as="xs:string">
    <xsl:sequence select="(normalize-space($info/j:string[@key='title'])[. != ''], 'API reference')[1]"/>
  </xsl:function>

  <!-- A string usable as an XML id and a file name -->
  <xsl:function name="oa:ncname" as="xs:string">
    <xsl:param name="s" as="xs:string"/>
    <xsl:variable name="clean" select="replace(replace(replace($s, '[^A-Za-z0-9_.\-]+', '_'), '_+', '_'), '^[_.\-]+|[_.\-]+$', '')"/>
    <xsl:sequence select="if ($clean = '') then 'x' else if (matches($clean, '^[A-Za-z_]')) then $clean else 'x_' || $clean"/>
  </xsl:function>

  <xsl:function name="oa:regex-escape" as="xs:string">
    <xsl:param name="s" as="xs:string"/>
    <xsl:sequence select="replace($s, '([\\.\[\]\{\}\(\)\*\+\?\^\$\|\-])', '\\$1')"/>
  </xsl:function>

  <xsl:function name="oa:codeph-list" as="node()*">
    <xsl:param name="values" as="xs:anyAtomicType*"/>
    <xsl:for-each select="$values">
      <xsl:if test="position() gt 1">, </xsl:if>
      <codeph>{.}</codeph>
    </xsl:for-each>
  </xsl:function>

  <xsl:function name="oa:ext-link" as="node()*">
    <xsl:param name="url" as="xs:string?"/>
    <xsl:param name="text" as="xs:string?"/>
    <xsl:choose>
      <xsl:when test="normalize-space($url)">
        <xref href="{normalize-space($url)}" scope="external" format="html">{($text[normalize-space()], $url)[1]}</xref>
      </xsl:when>
      <xsl:otherwise><xsl:value-of select="$text"/></xsl:otherwise>
    </xsl:choose>
  </xsl:function>

  <xsl:function name="oa:status-text" as="xs:string">
    <xsl:param name="code" as="xs:string"/>
    <xsl:variable name="t" select="map{
      '100':'Continue','101':'Switching Protocols','200':'OK','201':'Created','202':'Accepted',
      '203':'Non-Authoritative Information','204':'No Content','205':'Reset Content','206':'Partial Content',
      '207':'Multi-Status','300':'Multiple Choices','301':'Moved Permanently','302':'Found','303':'See Other',
      '304':'Not Modified','307':'Temporary Redirect','308':'Permanent Redirect','400':'Bad Request',
      '401':'Unauthorized','402':'Payment Required','403':'Forbidden','404':'Not Found','405':'Method Not Allowed',
      '406':'Not Acceptable','408':'Request Timeout','409':'Conflict','410':'Gone','411':'Length Required',
      '412':'Precondition Failed','413':'Content Too Large','414':'URI Too Long','415':'Unsupported Media Type',
      '416':'Range Not Satisfiable','422':'Unprocessable Content','423':'Locked','428':'Precondition Required',
      '429':'Too Many Requests','500':'Internal Server Error','501':'Not Implemented','502':'Bad Gateway',
      '503':'Service Unavailable','504':'Gateway Timeout',
      'default':'Any other status','1XX':'Informational','2XX':'Success','3XX':'Redirection',
      '4XX':'Client error','5XX':'Server error'}"/>
    <xsl:variable name="k" select="if (lower-case($code) = 'default') then 'default' else upper-case($code)"/>
    <xsl:sequence select="if (exists($t($k))) then ' ' || $t($k) else ''"/>
  </xsl:function>

</xsl:stylesheet>
