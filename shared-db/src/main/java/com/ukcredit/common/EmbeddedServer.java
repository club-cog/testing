package com.ukcredit.common;

import org.eclipse.jetty.server.Server;
import org.eclipse.jetty.servlet.ServletContextHandler;
import org.eclipse.jetty.servlet.ServletHolder;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.servlet.DispatcherServlet;

/**
 * Replaces the old Tomcat WAR deployment (2016). Each service main() calls start().
 */
public final class EmbeddedServer {

    private static final Logger LOG = LoggerFactory.getLogger(EmbeddedServer.class);

    private EmbeddedServer() {
    }

    public static Server start(String serviceName, int defaultPort, String contextConfigLocation) throws Exception {
        int port = Integer.getInteger("port", defaultPort);
        Server server = new Server(port);
        ServletContextHandler ctx = new ServletContextHandler(ServletContextHandler.NO_SESSIONS);
        ctx.setContextPath("/");
        DispatcherServlet dispatcher = new DispatcherServlet();
        dispatcher.setContextConfigLocation(contextConfigLocation);
        ServletHolder holder = new ServletHolder("dispatcher", dispatcher);
        holder.setInitOrder(1);
        ctx.addServlet(holder, "/*");
        server.setHandler(ctx);
        server.start();
        LOG.info("{} listening on port {}", serviceName, port);
        return server;
    }
}
