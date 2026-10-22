package com.ukcredit.db;

import java.io.InputStream;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.Properties;

/**
 * Reads db.properties (system properties override) for the command line tools.
 */
public final class DbConfig {

    private final Properties props = new Properties();

    public DbConfig() {
        InputStream in = DbConfig.class.getClassLoader().getResourceAsStream("db.properties");
        try {
            props.load(in);
            in.close();
        } catch (Exception e) {
            throw new IllegalStateException("cannot load db.properties", e);
        }
    }

    public String get(String key) {
        String sys = System.getProperty(key);
        return sys != null ? sys : props.getProperty(key);
    }

    public String url() { return get("jdbc.url"); }
    public String user() { return get("jdbc.username"); }
    public String password() { return get("jdbc.password"); }

    public Connection open() throws SQLException {
        try {
            Class.forName(get("jdbc.driverClassName"));
        } catch (ClassNotFoundException e) {
            throw new SQLException(e);
        }
        return DriverManager.getConnection(url(), user(), password());
    }
}
