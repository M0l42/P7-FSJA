package com.openclassroom.devops.orion.microcrm;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.rest.core.config.RepositoryRestConfiguration;
import org.springframework.data.rest.webmvc.config.RepositoryRestConfigurer;
import org.springframework.web.servlet.config.annotation.CorsRegistry;

@Configuration
public class SpringDataRestCustomization implements RepositoryRestConfigurer {

    /**
     * Origins allowed to call the API from a browser (CORS), comma-separated.
     * Set with the APP_CORS_ORIGINS environment variable; defaults to the local front end.
     */
    private final String[] allowedOrigins;

    public SpringDataRestCustomization(@Value("${app.cors.origins:http://localhost:4200}") String[] allowedOrigins) {
        this.allowedOrigins = allowedOrigins;
    }

    @Override
    public void configureRepositoryRestConfiguration(RepositoryRestConfiguration config, CorsRegistry cors) {
        config.exposeIdsFor(Person.class, Organization.class);
        cors.addMapping("/**")
                .allowedOrigins(allowedOrigins)
                .allowedMethods("GET", "POST", "PATCH", "DELETE")
                .exposedHeaders("Access-Control-Allow-Origin")
                .allowCredentials(false).maxAge(3600);
        RepositoryRestConfigurer.super.configureRepositoryRestConfiguration(config, cors);
    }
}
