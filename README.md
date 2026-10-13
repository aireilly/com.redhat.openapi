# openapi2dita: DITA-OT plugin

Generates a DITA map and DITA topics from an OpenAPI 3.0/3.1 or Swagger 2.0
description, in YAML or JSON. The output is plain DITA 1.3 (concept and
reference topics) that you can edit, reuse, and publish with any DITA-OT
transtype.

Tested with DITA-OT 4.2.4 on Java 21. It should also work with other DITA-OT 4.x releases.

## Install

Get the ZIP from the [latest release](https://github.com/aireilly/com.redhat.openapi/releases/latest):

```
curl -L -o openapi2dita.zip https://github.com/aireilly/com.redhat.openapi/releases/latest/download/openapi2dita.zip
dita install openapi2dita.zip
```

Push a version tag, such as `0.0.1`, to publish the ZIP as a GitHub release. The ZIP is ready to install with `dita install`.

## Use

```
dita --input=api.yaml --format=openapi2dita --output=out/api-dita
dita --input=out/api-dita/api.ditamap --format=html5 --output=out/html
```

The first command writes the DITA source. The second publishes it like any
other map. You can also reference the generated map from your own map with a
`mapref`.

### Parameters

| Parameter | Values | Default | Effect |
|---|---|---|---|
| `openapi.group-by` | `tag`, `path`, `none` | `tag` | How operations are grouped in the map |
| `openapi.map-name` | file name | input file name | Name of the `.ditamap` |
| `openapi.lang` | language code | `en-US` | `xml:lang` on every map and topic |
| `openapi.curl` | `yes`, `no` | `yes` | Add an example curl request to each operation |
| `openapi.schemas` | `yes`, `no` | `yes` | Write a topic for each named schema |
| `openapi.markdown` | `yes`, `no` | `yes` | Convert Markdown descriptions to DITA markup |

Use this to group APIs by path:

```
dita --input=api.yaml --format=openapi2dita -o out --openapi.group-by=path
```

## Output

```
api.ditamap
overview.dita            concept: description, version, contact, licence, servers, authentication
tags/tag_<name>.dita     concept per tag that has a description (operations nest under it)
operations/<id>.dita     reference per operation
schemas/<name>.dita      reference per named schema (components/schemas or definitions)
```

Each operation topic has these parts:

* The title (from `summary`) and a second-level heading with the HTTP method and path.
* A `refsyn` holding the full request line.
* The description, authorization requirements, and a parameters table.
* The request body: content types, a link to the schema, a property table for inline schemas, and an example.
* A responses table with status, description, headers, and body schema, plus property tables for inline response bodies.
* An example curl request and an example response.
* Related links to the data models the operation uses.

Each schema topic has these parts:

* The description and type.
* Inheritance (`allOf`) and alternatives (`oneOf`/`anyOf`).
* A property table. Nested inline objects are flattened to `parent.child` and `items[].child`, and `allOf` properties are merged in.
* Notes on allowed values, defaults, constraints, and read-only or write-only properties.
* An example.
* "Used by" links back to the operations and schemas that reference it.

Topic file names and IDs come from `operationId` (or from `method_path` when an
operation has no `operationId`) and from schema names, made safe for XML IDs and file systems.

## What's supported

* OpenAPI 3.0 and 3.1, and Swagger 2.0. This covers Swagger 2 `body` and `formData` parameters, `consumes`/`produces`, and `securityDefinitions`.
* `$ref` to local components (parameters, responses, request bodies, headers, examples, schemas).
* `$ref` to other files (`./schemas/Pet.yaml`, `common.yaml#/components/schemas/Error`). Schemas from other files become schema topics. Other components are copied in where they are used.
* Path-level parameters merged with operation-level ones.
* OpenAPI 3.1 webhooks, under a "Webhooks" heading.
* Markdown in descriptions, through the Markdown parser in DITA-OT's bundled `org.lwdita` plugin. If that plugin isn't there, basic formatting (paragraphs, lists, code, bold, links) is used instead.
* When no example is given, examples are built from the schema using property examples, defaults, enums, and type placeholders.

## Limitations

* Callbacks, `links`, and `x-` extensions other than `x-displayName` on tags are not documented.
* Refs to remote `http(s)` URLs only work if the machine running DITA-OT can reach them.
* Relative links inside Markdown descriptions are converted to plain text, because their targets don't exist in the DITA output.

## Customising

The DITA is produced by one XSLT 3.0 stylesheet, `xsl/openapi2dita.xsl`, run with
Saxon (bundled with DITA-OT). Change it to alter titles, table layouts, section
order, or topic types. The Java part (`src/`) only parses YAML/JSON, bundles
external refs, and runs the stylesheet.

To rebuild `lib/openapi2dita.jar` after changing the Java:

```
DITA_HOME=/path/to/dita-ot ./build-jar.sh
```

After you edit the plugin source in place, run `dita install` with no arguments to re-integrate it.

## Samples

`samples/` has three examples:

* `bookshop.yaml` (OpenAPI 3.0) uses most of the features above.
* `petstore-swagger2.json` (Swagger 2.0) is the OpenAPI Initiative's petstore-expanded example.
* `multi-file/` is a specification split across several files.
