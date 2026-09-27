// Copyright (c) 2023, 2025, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

package com.example.checks;

import java.sql.SQLException;
import javax.sql.DataSource;

import com.example.common.filter.LoggingFilterConfig;
import jakarta.jms.ConnectionFactory;
import jakarta.jms.JMSException;
import lombok.extern.slf4j.Slf4j;
import oracle.jakarta.jms.AQjmsFactory;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.jms.autoconfigure.DefaultJmsListenerContainerFactoryConfigurer;
import org.springframework.cloud.client.discovery.EnableDiscoveryClient;
import org.springframework.cloud.openfeign.EnableFeignClients;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.jms.annotation.EnableJms;
import org.springframework.jms.config.DefaultJmsListenerContainerFactory;
import org.springframework.jms.config.JmsListenerContainerFactory;
import org.springframework.jms.core.JmsTemplate;
import org.springframework.jms.support.converter.JacksonJsonMessageConverter;
import org.springframework.jms.support.converter.MessageConverter;
import org.springframework.jms.support.converter.MessageType;

@SpringBootApplication
@EnableFeignClients
@EnableJms
@EnableDiscoveryClient
@Import(LoggingFilterConfig.class)
@Slf4j
public class ChecksApplication {

    /**
     * Application main class.
     * 
     * @param args - main arguments
     */
    public static void main(String[] args) {
        SpringApplication.run(ChecksApplication.class, args);
    }

    /**
     * Serialize message content to json using TextMessage.
     * 
     * @return TO-DO
     */
    @Bean
    public MessageConverter jacksonJmsMessageConverter() {
        JacksonJsonMessageConverter converter = new JacksonJsonMessageConverter();
        converter.setTargetType(MessageType.TEXT);
        converter.setTypeIdPropertyName("_type");
        return converter;
    }

    /**
     * TO-DO.
     * 
     * @param connectionFactory TO-DO
     * @return TO-DO
     */
    @Bean
    public JmsTemplate jmsTemplate(ConnectionFactory connectionFactory) {
        JmsTemplate jmsTemplate = new JmsTemplate();
        jmsTemplate.setConnectionFactory(connectionFactory);
        jmsTemplate.setMessageConverter(jacksonJmsMessageConverter());
        return jmsTemplate;
    }

    /**
     * TO-DO.
     * 
     * @param connectionFactory TO-DO
     * @param configurer        TO-DO
     * @return TO-DO
     */
    @Bean
    public JmsListenerContainerFactory<?> factory(ConnectionFactory connectionFactory,
            DefaultJmsListenerContainerFactoryConfigurer configurer) {
        DefaultJmsListenerContainerFactory factory = new DefaultJmsListenerContainerFactory();
        // This provides all boot's default to this factory, including the message
        // converter
        configurer.configure(factory, connectionFactory);
        // You could still override some of Boot's default if necessary.
        return factory;
    }

    /**
     * Initialize AQ JMS ConnectionFactory.
     * 
     * @param ds Oracle Datasource.
     * @return ConnectionFactory The AQ JMS ConnectionFactory.
     * @throws JMSException when an error is encountered while creating a JMS
     *                      ConnectionFactory.
     * @throws SQLException when an error is encountered while accessing backing
     *                      Oracle DataSource.
     */
    @Bean
    public ConnectionFactory aqJmsConnectionFactory(DataSource ds) throws JMSException, SQLException {
        return AQjmsFactory.getConnectionFactory(ds.unwrap(DataSource.class));
    }

}
