package openapi2dita;

import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.JsonNodeFactory;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.fasterxml.jackson.dataformat.yaml.YAMLFactory;
import net.sf.saxon.s9api.NullDestination;
import net.sf.saxon.s9api.Processor;
import net.sf.saxon.s9api.QName;
import net.sf.saxon.s9api.SaxonApiException;
import net.sf.saxon.s9api.XdmAtomicValue;
import net.sf.saxon.s9api.XdmValue;
import net.sf.saxon.s9api.XsltCompiler;
import net.sf.saxon.s9api.XsltExecutable;
import net.sf.saxon.s9api.Xslt30Transformer;
import org.apache.tools.ant.BuildException;
import org.apache.tools.ant.Project;
import org.apache.tools.ant.Task;
import org.yaml.snakeyaml.LoaderOptions;

import javax.xml.transform.stream.StreamSource;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.HashMap;
import java.util.Map;

/**
 * Ant task that reads an OpenAPI 3.x or Swagger 2.0 description (YAML or JSON)
 * and writes a DITA map plus DITA topics using the plugin's XSLT stylesheet.
 */
public class OpenApiToDitaTask extends Task {

    private String src;
    private File destDir;
    private File style;
    private String mapName;
    private String lang = "en-US";
    private String groupBy = "tag";
    private String includeCurl = "yes";
    private String includeSchemas = "yes";
    private String markdown = "yes";

    public void setSrc(String src) { this.src = src; }
    public void setDestdir(File destDir) { this.destDir = destDir; }
    public void setStyle(File style) { this.style = style; }
    public void setMapname(String mapName) { this.mapName = mapName; }
    public void setLang(String lang) { this.lang = lang; }
    public void setGroupby(String groupBy) { this.groupBy = groupBy; }
    public void setIncludecurl(String v) { this.includeCurl = v; }
    public void setIncludeschemas(String v) { this.includeSchemas = v; }
    public void setMarkdown(String v) { this.markdown = v; }

    @Override
    public void execute() throws BuildException {
        if (src == null || src.isBlank()) throw new BuildException("openapi2dita: no input specified (use --input)");
        if (destDir == null) throw new BuildException("openapi2dita: no output directory specified");
        if (style == null || !style.isFile()) throw new BuildException("openapi2dita: stylesheet not found: " + style);

        URI uri = toUri(src);
        String name = baseName(uri.getPath());
        log("Reading " + uri, Project.MSG_INFO);
        JsonNode node = parse(read(uri));
        if (node == null || !node.isObject() || !(node.has("openapi") || node.has("swagger"))) {
            throw new BuildException("openapi2dita: input is not an OpenAPI 3.x or Swagger 2.0 document "
                    + "(no top-level 'openapi' or 'swagger' field)");
        }
        RefBundler bundler = new RefBundler((ObjectNode) node, uri, u -> parse(read(u)));
        bundler.bundle();
        for (String w : bundler.warnings().split("\n")) {
            if (!w.isBlank()) log(w, Project.MSG_WARN);
        }
        String json;
        try {
            json = new ObjectMapper().writeValueAsString(node);
        } catch (IOException e) {
            throw new BuildException(e);
        }
        if (mapName == null || mapName.isBlank()) mapName = name;

        try {
            Files.createDirectories(destDir.toPath());
            Processor processor = new Processor(false);
            if (!"no".equalsIgnoreCase(markdown)) {
                MarkdownFunction md = MarkdownFunction.create(processor);
                if (md != null) {
                    processor.registerExtensionFunction(md);
                } else {
                    log("Markdown parser (org.lwdita plugin) not found; descriptions use basic formatting", Project.MSG_WARN);
                }
            }
            XsltCompiler compiler = processor.newXsltCompiler();
            XsltExecutable exec = compiler.compile(new StreamSource(style));
            Xslt30Transformer t = exec.load30();
            Map<QName, XdmValue> params = new HashMap<>();
            params.put(new QName("json"), new XdmAtomicValue(json));
            params.put(new QName("map-name"), new XdmAtomicValue(mapName));
            params.put(new QName("lang"), new XdmAtomicValue(lang));
            params.put(new QName("group-by"), new XdmAtomicValue(groupBy));
            params.put(new QName("include-curl"), new XdmAtomicValue(includeCurl));
            params.put(new QName("include-schemas"), new XdmAtomicValue(includeSchemas));
            t.setStylesheetParameters(params);
            t.setMessageHandler(m -> log(m.getContent().getStringValue(),
                    m.isTerminate() ? Project.MSG_ERR : Project.MSG_INFO));
            String base = destDir.getAbsoluteFile().toURI().toString();
            t.setBaseOutputURI(base.endsWith("/") ? base : base + "/");
            t.callTemplate(new QName("main"), new NullDestination());
            log("Wrote " + new File(destDir, mapName + ".ditamap"), Project.MSG_INFO);
        } catch (SaxonApiException | IOException e) {
            throw new BuildException("openapi2dita: conversion failed: " + e.getMessage(), e);
        }
    }

    static String read(URI uri) {
        try (InputStream in = uri.toURL().openStream()) {
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new BuildException("openapi2dita: cannot read " + uri + ": " + e.getMessage(), e);
        }
    }

    /** Parses YAML or JSON into a Jackson tree. */
    static JsonNode parse(String text) {
        ObjectMapper reader;
        String trimmed = text.stripLeading();
        if (trimmed.startsWith("\uFEFF")) trimmed = trimmed.substring(1);
        if (trimmed.startsWith("{")) {
            reader = new ObjectMapper();
        } else {
            LoaderOptions opts = new LoaderOptions();
            opts.setCodePointLimit(256 * 1024 * 1024);
            opts.setMaxAliasesForCollections(1000);
            reader = new ObjectMapper(YAMLFactory.builder().loaderOptions(opts).build());
        }
        // keep the decimal scale of numbers like 1.10
        reader.enable(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS);
        reader.setNodeFactory(JsonNodeFactory.withExactBigDecimals(true));
        try {
            return reader.readTree(trimmed);
        } catch (IOException e) {
            throw new BuildException("openapi2dita: not valid YAML or JSON: " + e.getMessage(), e);
        }
    }

    static URI toUri(String s) {
        if (s.matches("^[a-zA-Z][a-zA-Z0-9+.-]+:.*") && !s.matches("^[a-zA-Z]:[\\\\/].*")) {
            try {
                URI u = new URI(s);
                if (u.isAbsolute()) return u;
            } catch (Exception e) {
                // fall through and treat it as a path
            }
        }
        return new File(s).getAbsoluteFile().toURI();
    }

    static String baseName(String path) {
        if (path == null || path.isEmpty()) return "api";
        String n = path.substring(path.lastIndexOf('/') + 1);
        int dot = n.lastIndexOf('.');
        if (dot > 0) n = n.substring(0, dot);
        n = n.replaceAll("[^A-Za-z0-9._-]", "_");
        return n.isEmpty() ? "api" : n;
    }
}
