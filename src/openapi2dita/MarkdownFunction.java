package openapi2dita;

import net.sf.saxon.s9api.DocumentBuilder;
import net.sf.saxon.s9api.ExtensionFunction;
import net.sf.saxon.s9api.ItemType;
import net.sf.saxon.s9api.OccurrenceIndicator;
import net.sf.saxon.s9api.Processor;
import net.sf.saxon.s9api.QName;
import net.sf.saxon.s9api.SequenceType;
import net.sf.saxon.s9api.XdmEmptySequence;
import net.sf.saxon.s9api.XdmValue;
import org.xml.sax.InputSource;
import org.xml.sax.XMLReader;

import javax.xml.transform.sax.SAXSource;
import java.io.StringReader;

/**
 * XPath extension function md:markdown($text as xs:string) as document-node()?
 * Converts CommonMark text to a DITA topic using the Markdown parser that ships
 * with DITA-OT (org.lwdita plugin). Returns an empty sequence if parsing fails.
 */
public class MarkdownFunction implements ExtensionFunction {

    public static final String NS = "urn:openapi2dita:markdown";
    private static final String READER_CLASS = "com.elovirta.dita.markdown.MarkdownReader";

    private final DocumentBuilder builder;
    private final Class<?> readerClass;

    private MarkdownFunction(Processor processor, Class<?> readerClass) {
        this.builder = processor.newDocumentBuilder();
        this.readerClass = readerClass;
    }

    /** Returns null when the lwdita Markdown parser isn't on the classpath. */
    public static MarkdownFunction create(Processor processor) {
        try {
            Class<?> c = Class.forName(READER_CLASS, true, MarkdownFunction.class.getClassLoader());
            return new MarkdownFunction(processor, c);
        } catch (ClassNotFoundException | LinkageError e) {
            try {
                Class<?> c = Class.forName(READER_CLASS, true, Thread.currentThread().getContextClassLoader());
                return new MarkdownFunction(processor, c);
            } catch (ClassNotFoundException | LinkageError e2) {
                return null;
            }
        }
    }

    @Override
    public QName getName() {
        return new QName(NS, "markdown");
    }

    @Override
    public SequenceType getResultType() {
        return SequenceType.makeSequenceType(ItemType.DOCUMENT_NODE, OccurrenceIndicator.ZERO_OR_ONE);
    }

    @Override
    public SequenceType[] getArgumentTypes() {
        return new SequenceType[]{SequenceType.makeSequenceType(ItemType.STRING, OccurrenceIndicator.ONE)};
    }

    @Override
    public XdmValue call(XdmValue[] args) {
        String text = args[0].itemAt(0).getStringValue();
        try {
            XMLReader reader = (XMLReader) readerClass.getDeclaredConstructor().newInstance();
            return builder.build(new SAXSource(reader, new InputSource(new StringReader(text))));
        } catch (Exception | LinkageError e) {
            return XdmEmptySequence.getInstance();
        }
    }
}
