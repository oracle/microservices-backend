// Copyright (c) 2023, 2026, Oracle and/or its affiliates.

package com.cloudbank.aznserver.controller;

import java.util.Arrays;

import com.cloudbank.aznserver.securityconfig.SecurityConfig;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.security.access.hierarchicalroles.RoleHierarchy;
import org.springframework.security.access.hierarchicalroles.RoleHierarchyImpl;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.crypto.password.Pbkdf2PasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.provisioning.InMemoryUserDetailsManager;
import org.springframework.security.web.SecurityFilterChain;

import static org.springframework.security.config.Customizer.withDefaults;

@TestConfiguration
@EnableWebSecurity
@EnableMethodSecurity
public class TestSecurityConfig {
    
    /**
     * Configure a role hierarchy such that ADMIN "includes"/implies USER.
     * 
     * @return the hierarchy.
     */

    @Bean
    public RoleHierarchy roleHierarchy() {
        return RoleHierarchyImpl.fromHierarchy(SecurityConfig.ROLE_HIERARCHY);
    }

    /**
     * Create an in-memory UserDetailsService populated with some test users.
     * @return the UserDetailsService.
     */
    @Bean
    @Primary
    public UserDetailsService userDetailsService() {
        PasswordEncoder encoder = passwordEncoder();

        UserDetails obaasUser = User.builder()
                .username("obaas-user")
                .password(encoder.encode("password"))
                .roles("USER")
                .build();
        UserDetails obaasAdmin = User.builder()
                .username("obaas-admin")
                .password(encoder.encode("password"))
                .roles("ADMIN")
                .build();
        UserDetails obaasContent = User.builder()
                .username("obaas-content")
                .password(encoder.encode("password"))
                .roles("CONFIG_EDITOR")
                .build();  
        return new InMemoryUserDetailsManager(Arrays.asList(obaasUser, obaasAdmin, obaasContent));
    }

    @Bean
    @Primary
    public PasswordEncoder passwordEncoder() {
        return Pbkdf2PasswordEncoder.defaultsForSpringSecurity_v5_8();
    }

    /**
     * Create a SecurityFilterChain with basic authentication using the in-memory test
     * UserDetailsService.
     * 
     * @param http HttpService injected by Spring.
     * @return the SecurityFilterChain.
     * @throws Exception if unable to create the chain.
     */
    @Bean
    @Primary
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        return http
            .csrf(AbstractHttpConfigurer::disable)
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/error/**").permitAll()
                .anyRequest().authenticated())
            .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .httpBasic(withDefaults())
            .userDetailsService(userDetailsService())
            .build();
    }
}
