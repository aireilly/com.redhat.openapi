package openapi2dita;

import com.fasterxml.jackson.core.JsonPointer;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.fasterxml.jackson.databind.node.TextNode;

import java.net.URI;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;
import java.util.function.Function;

/**
 * Pulls $refs to other files into the main document, so the stylesheet only
 * sees local (#/...) references. Schemas from other files are added to
 * components/schemas (or definitions) and referenced by name; anything else
 * (parameters, responses, examples...) is copied in place.
 */
final class RefBundler {

    private static final String[] SCHEMA_KEYS = {"type", "properties", "allOf", "oneOf", "anyOf", "enum", "items", "additionalProperties"};

    private final ObjectNode root;
    private final URI rootUri;
    private final boolean v2;
    private final Function<URI, JsonNode> loader;
    private final Map<URI, JsonNode> cache = new HashMap<>();
    private final Map<String, String> hoisted = new HashMap<>();
    private final Deque<String> inlining = new ArrayDeque<>();
    private final StringBuilder warnings = new StringBuilder();

    RefBundler(ObjectNode root, URI rootUri, Function<URI, JsonNode> loader) {
        this.root = root;
        this.rootUri = rootUri;
        this.v2 = root.has("swagger");
        this.loader = loader;
        cache.put(stripFragment(rootUri), root);
    }

    String warnings() { return warnings.toString(); }

    void bundle() {
        walk(root, rootUri);
    }

    private void walk(JsonNode node, URI base) {
        if (node.isObject()) {
            ObjectNode obj = (ObjectNode) node;
            Iterator<Map.Entry<String, JsonNode>> it = obj.fields();
            while (it.hasNext()) {
                Map.Entry<String, JsonNode> e = it.next();
                JsonNode child = e.getValue();
                if (child.isObject() && child.path("$ref").isTextual()) {
                    JsonNode replacement = resolveRef((ObjectNode) child, base);
                    if (replacement != child) {
                        e.setValue(replacement);
                        continue;
                    }
                }
                walk(child, base);
            }
        } else if (node.isArray()) {
            for (int i = 0; i < node.size(); i++) {
                JsonNode child = node.get(i);
                if (child.isObject() && child.path("$ref").isTextual()) {
                    JsonNode replacement = resolveRef((ObjectNode) child, base);
                    if (replacement != child) {
                        ((com.fasterxml.jackson.databind.node.ArrayNode) node).set(i, replacement);
                        continue;
                    }
                }
                walk(child, base);
            }
        }
    }

    /** Returns the node to use in place of refNode (refNode itself if it stays as is). */
    private JsonNode resolveRef(ObjectNode refNode, URI base) {
        String ref = refNode.get("$ref").asText();
        boolean inRootDoc = stripFragment(base).equals(stripFragment(rootUri));
        if (ref.startsWith("#") && inRootDoc) {
            return refNode; // local ref in the main document: keep
        }
        URI target;
        try {
            target = base.resolve(ref.startsWith("#") ? ref : encodePath(ref));
        } catch (IllegalArgumentException ex) {
            warn("Cannot resolve $ref " + ref);
            return refNode;
        }
        URI file = stripFragment(target);
        String fragment = target.getRawFragment() == null ? "" : decode(target.getRawFragment());
        if (file.equals(stripFragment(rootUri))) {
            // a ref from another file back into the main document
            refNode.put("$ref", "#" + fragment);
            return refNode;
        }
        JsonNode doc = cache.computeIfAbsent(file, u -> {
            try {
                return loader.apply(u);
            } catch (RuntimeException ex) {
                warn("Cannot read " + u + ": " + ex.getMessage());
                return null;
            }
        });
        if (doc == null) return refNode;
        JsonNode t = fragment.isEmpty() ? doc : doc.at(JsonPointer.compile(fragment));
        if (t.isMissingNode()) {
            warn("$ref target not found: " + target);
            return refNode;
        }
        String key = file + "#" + fragment;
        if (isSchemaRef(fragment, t)) {
            String local = hoisted.get(key);
            if (local == null) {
                String name = schemaName(fragment, file);
                local = (v2 ? "#/definitions/" : "#/components/schemas/") + escape(name);
                hoisted.put(key, local);
                JsonNode copy = t.deepCopy();
                schemasNode().set(name, copy);
                // the copy's own refs are relative to its file
                walkCopy(copy, file);
            }
            ObjectNode out = refNode.deepCopy();
            out.put("$ref", local);
            return out;
        }
        if (inlining.contains(key)) {
            warn("Circular $ref left unresolved: " + ref);
            return refNode;
        }
        inlining.push(key);
        try {
            JsonNode copy = t.deepCopy();
            if (copy.isObject() && copy.path("$ref").isTextual()) {
                copy = resolveRef((ObjectNode) copy, file);
            }
            walkCopy(copy, file);
            return copy;
        } finally {
            inlining.pop();
        }
    }

    private void walkCopy(JsonNode copy, URI file) {
        walk(copy, file);
    }

    private boolean isSchemaRef(String fragment, JsonNode t) {
        if (fragment.matches(".*/(schemas|definitions)/[^/]+")) return true;
        if (!fragment.isEmpty() || !t.isObject()) return false;
        if (t.has("in") || t.has("content") || t.has("paths") || t.has("openapi") || t.has("swagger")) return false;
        for (String k : SCHEMA_KEYS) {
            if (t.has(k)) return true;
        }
        return false;
    }

    private String schemaName(String fragment, URI file) {
        String base;
        if (!fragment.isEmpty()) {
            base = fragment.substring(fragment.lastIndexOf('/') + 1).replace("~1", "/").replace("~0", "~");
        } else {
            base = OpenApiToDitaTask.baseName(file.getPath());
        }
        ObjectNode schemas = schemasNode();
        String name = base;
        int n = 2;
        while (schemas.has(name)) {
            name = base + "_" + n++;
        }
        return name;
    }

    private ObjectNode schemasNode() {
        if (v2) {
            return root.has("definitions") ? (ObjectNode) root.get("definitions") : root.putObject("definitions");
        }
        ObjectNode components = root.has("components") ? (ObjectNode) root.get("components") : root.putObject("components");
        return components.has("schemas") ? (ObjectNode) components.get("schemas") : components.putObject("schemas");
    }

    private void warn(String s) {
        warnings.append(s).append('\n');
    }

    private static URI stripFragment(URI u) {
        try {
            return new URI(u.getScheme(), u.getSchemeSpecificPart(), null);
        } catch (Exception e) {
            return u;
        }
    }

    private static String escape(String name) {
        return name.replace("~", "~0").replace("/", "~1");
    }

    private static String decode(String s) {
        try {
            return java.net.URLDecoder.decode(s.replace("+", "%2B"), "UTF-8");
        } catch (Exception e) {
            return s;
        }
    }

    /** Encodes spaces etc. in the path part of a relative ref so URI.resolve accepts it. */
    private static String encodePath(String ref) {
        int hash = ref.indexOf('#');
        String path = hash >= 0 ? ref.substring(0, hash) : ref;
        String frag = hash >= 0 ? ref.substring(hash) : "";
        if (path.matches("^[a-zA-Z][a-zA-Z0-9+.-]*:.*")) return ref;
        return path.replace("%", "%25").replace(" ", "%20") + frag.replace(" ", "%20");
    }

    static TextNode text(String s) { return TextNode.valueOf(s); }
}
