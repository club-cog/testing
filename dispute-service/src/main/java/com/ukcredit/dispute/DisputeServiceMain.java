package com.ukcredit.dispute;

import com.ukcredit.common.EmbeddedServer;

public class DisputeServiceMain {

    public static void main(String[] args) throws Exception {
        EmbeddedServer.start("dispute-service", 8083, "classpath:META-INF/spring/dispute-servlet.xml").join();
    }
}
