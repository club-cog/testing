package com.ukcredit.batch;

import org.springframework.context.support.ClassPathXmlApplicationContext;

import java.io.File;

/**
 * Nightly lender file load. Usage: BatchIngestMain &lt;file&gt;
 * Exit code 0 = loaded (possibly with rejects), 1 = file failed.
 */
public class BatchIngestMain {

    public static void main(String[] args) throws Exception {
        if (args.length != 1) {
            System.err.println("usage: BatchIngestMain <lender-file>");
            System.exit(2);
        }
        ClassPathXmlApplicationContext ctx = new ClassPathXmlApplicationContext("META-INF/spring/batch-context.xml");
        int rc;
        try {
            LenderFileLoader loader = ctx.getBean("lenderFileLoader", LenderFileLoader.class);
            rc = loader.load(new File(args[0])) ? 0 : 1;
        } finally {
            ctx.close();
        }
        System.exit(rc);
    }
}
