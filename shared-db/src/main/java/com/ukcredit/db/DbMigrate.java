package com.ukcredit.db;

import org.flywaydb.core.Flyway;

/**
 * Applies the Flyway scripts in db/migration. Run before starting any service.
 * Usage: java -cp shared-db-tools.jar com.ukcredit.db.DbMigrate [clean]
 */
public class DbMigrate {

    public static void main(String[] args) {
        DbConfig cfg = new DbConfig();
        Flyway flyway = new Flyway();
        flyway.setDataSource(cfg.url(), cfg.user(), cfg.password());
        flyway.setLocations("classpath:db/migration");
        if (args.length > 0 && "clean".equals(args[0])) {
            flyway.clean();
        }
        int applied = flyway.migrate();
        System.out.println("Flyway: applied " + applied + " migration(s) to " + cfg.url());
    }
}
