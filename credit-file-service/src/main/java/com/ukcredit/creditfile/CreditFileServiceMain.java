package com.ukcredit.creditfile;

import com.ukcredit.common.EmbeddedServer;

public class CreditFileServiceMain {

    public static void main(String[] args) throws Exception {
        EmbeddedServer.start("credit-file-service", 8081, "classpath:META-INF/spring/creditfile-servlet.xml").join();
    }
}
