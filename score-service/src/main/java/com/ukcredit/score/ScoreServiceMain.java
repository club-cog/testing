package com.ukcredit.score;

import com.ukcredit.common.EmbeddedServer;

public class ScoreServiceMain {

    public static void main(String[] args) throws Exception {
        EmbeddedServer.start("score-service", 8082, "classpath:META-INF/spring/score-servlet.xml").join();
    }
}
