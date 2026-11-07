package kz.jolay.common;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ReadListener;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletInputStream;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletRequestWrapper;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

/**
 * Refuses oversized JSON request bodies before they are parsed. Jackson would otherwise read an arbitrarily large body into memory for every
 * request, including unauthenticated ones such as login. The real JSON requests of the apps are a few hundred bytes; the default limit is 256 KB.
 * Multipart uploads (driver documents) are limited separately by {@code spring.servlet.multipart.*} and by DocumentService.
 * A declared Content-Length over the limit is answered with 413 immediately; a body that does not declare its length (chunked) is cut off once it
 * passes the limit while being read.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 5)
public class RequestSizeLimitFilter extends OncePerRequestFilter {
    private final long maxBytes;

    public RequestSizeLimitFilter(@Value("${jolay.limits.max-json-body-bytes:262144}") long maxBytes) { this.maxBytes = maxBytes; }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest r) {
        String type = r.getContentType();
        return type == null || !type.toLowerCase().startsWith("application/json");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain) throws ServletException, IOException {
        if (req.getContentLengthLong() > maxBytes) {
            res.setStatus(HttpServletResponse.SC_REQUEST_ENTITY_TOO_LARGE);
            res.setContentType("application/json");
            res.getWriter().write("{\"code\":\"payload_too_large\",\"message\":\"Request body is too large\"}");
            return;
        }
        chain.doFilter(req.getContentLengthLong() >= 0 ? req : new Limited(req, maxBytes), res);
    }

    /** Counts the bytes of a body with no declared length and fails the read once the limit is passed. */
    private static final class Limited extends HttpServletRequestWrapper {
        private final long max;
        Limited(HttpServletRequest r, long max) { super(r); this.max = max; }

        @Override
        public ServletInputStream getInputStream() throws IOException {
            ServletInputStream in = super.getInputStream();
            return new ServletInputStream() {
                private long read;
                private int count(int b) throws IOException { if (b >= 0 && ++read > max) throw new IOException("request body too large"); return b; }
                @Override public int read() throws IOException { return count(in.read()); }
                @Override public int read(byte[] buf, int off, int len) throws IOException {
                    int n = in.read(buf, off, len);
                    if (n > 0 && (read += n) > max) throw new IOException("request body too large");
                    return n;
                }
                @Override public boolean isFinished() { return in.isFinished(); }
                @Override public boolean isReady() { return in.isReady(); }
                @Override public void setReadListener(ReadListener l) { in.setReadListener(l); }
            };
        }
    }
}
