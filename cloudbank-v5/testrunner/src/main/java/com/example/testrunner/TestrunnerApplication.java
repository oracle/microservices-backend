// Copyright (c) 2023, 2025, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

package com.example.testrunner;

import java.sql.SQLException;
import javax.sql.DataSource;

import com.example.common.filter.LoggingFilterConfig;
import jakarta.jms.ConnectionFactory;
import jakarta.jms.JMSException;
import oracle.jakarta.jms.AQjmsFactory;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.client.discovery.EnableDiscoveryClient;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.jms.annotation.EnableJms;
import org.springframework.jms.core.JmsTemplate;
import org.springframework.jms.support.converter.JacksonJsonMessageConverter;
import org.springframework.jms.support.converter.MessageConverter;
import org.springframework.jms.support.converter.MessageType;

// TO-DO Add Eureka
@SpringBootApplication
@EnableJms
@EnableDiscoveryClient
@Import(LoggingFilterConfig.class)
public class TestrunnerApplication {

    public static void main(String[] args) {
        SpringApplication.run(TestrunnerApplication.class, args);
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
