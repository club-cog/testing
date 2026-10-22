package com.ukcredit.db;

import org.flywaydb.core.Flyway;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.Statement;

/**
 * Applies the Flyway scripts in db/migration. Run before starting any service.
 * Usage: java -cp shared-db-tools.jar com.ukcredit.db.DbMigrate [clean]
 */
public class DbMigrate {

    public static void main(String[] args) throws SQLException {
        DbConfig cfg = new DbConfig();
        Flyway flyway = new Flyway();
        flyway.setDataSource(cfg.url(), cfg.user(), cfg.password());
        flyway.setLocations("classpath:db/migration");
        if (args.length > 0 && "clean".equals(args[0])) {
            if (cfg.url().startsWith("jdbc:postgresql:")) {
                // Flyway 4.2 clean breaks on PG 11+ (pg_proc.proisagg), drop the schema by hand
                dropPublicSchema(cfg);
            } else {
                flyway.clean();
            }
        }
        int applied = flyway.migrate();
        System.out.println("Flyway: applied " + applied + " migration(s) to " + cfg.url());
    }

    private static void dropPublicSchema(DbConfig cfg) throws SQLException {
        Connection c = DriverManager.getConnection(cfg.url(), cfg.user(), cfg.password());
        try {
            Statement st = c.createStatement();
            st.execute("DROP SCHEMA public CASCADE");
            st.execute("CREATE SCHEMA public");
            st.close();
        } finally {
            c.close();
        }
    }
}
