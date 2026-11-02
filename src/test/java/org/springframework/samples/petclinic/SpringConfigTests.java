package org.springframework.samples.petclinic;

import java.util.Properties;

import com.zaxxer.hikari.HikariDataSource;
import org.junit.jupiter.api.Test;
import org.postgresql.Driver;
import org.springframework.boot.autoconfigure.AutoConfigurations;
import org.springframework.boot.jdbc.autoconfigure.DataSourceAutoConfiguration;
import org.springframework.boot.test.context.ConfigDataApplicationContextInitializer;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

@SpringBootTest(classes = PetClinicApplication.class)
class SpringConfigTests {

    @Test
    void applicationBindsIdentityAndTlsWithoutLongJdbcUrl() {
        new ApplicationContextRunner()
            .withConfiguration(AutoConfigurations.of(DataSourceAutoConfiguration.class))
            .withInitializer(new ConfigDataApplicationContextInitializer())
            .withPropertyValues(
                "spring.config.location=file:./src/main/resources/",
                "POSTGRES_URL=jdbc:postgresql://test.postgres.database.azure.com:5432/petclinic")
            .run(context -> {
                HikariDataSource datasource = context.getBean(HikariDataSource.class);
                assertEquals("jdbc:postgresql://test.postgres.database.azure.com:5432/petclinic",
                    datasource.getJdbcUrl());
                assertEquals("petclinic_app", datasource.getUsername());
                assertNull(datasource.getPassword());
                Properties options = Driver.parseURL(datasource.getJdbcUrl(), datasource.getDataSourceProperties());
                assertEquals("com.azure.identity.extensions.jdbc.postgresql.AzurePostgresqlAuthenticationPlugin",
                    options.getProperty("authenticationPluginClassName"));
                assertEquals("true", options.getProperty("azure.managedIdentityEnabled"));
                assertNull(options.getProperty("azure.clientId"));
                assertEquals("verify-full", options.getProperty("sslmode"));
                assertEquals("/etc/ssl/certs/ca-certificates.crt", options.getProperty("sslrootcert"));
                assertEquals("postgres", context.getEnvironment().getProperty("spring.sql.init.platform"));
            });
    }

    @Test
    void contextLoads() {
        // Test the Spring configuration
    }
}
