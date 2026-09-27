// Copyright (c) 2023, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

package com.example.customer.model;

import java.util.Date;

import com.fasterxml.jackson.annotation.JsonIgnore;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.Generated;
import org.hibernate.generator.EventType;

@SuppressWarnings("deprecation")
@Entity
@Table(name = "CUSTOMERS")
@Data
@NoArgsConstructor
public class Customers {

    @Id
    @Column(name = "CUSTOMER_ID")
    private String customerId;

    @Column(name = "CUSTOMER_NAME")
    private String customerName;

    @Column(name = "CUSTOMER_EMAIL")
    private String customerEmail;

    @Generated(event = EventType.INSERT)
    @Column(name = "DATE_BECAME_CUSTOMER", updatable = false, insertable = false)
    private Date dateBecameCustomer;

    @Column(name = "CUSTOMER_OTHER_DETAILS")
    private String customerOtherDetails;

    @Column(name = "PASSWORD")
    @JsonIgnore
    private String customerPassword;


    /**
     * Creates a  Customers object.
     * @param customerId The Customer ID
     * @param customerName The Customer Name
     * @param customerEmail The Customer Email
     * @param customerOtherDetails Other details about the customer
     */
    public Customers(String customerId, String customerName, String customerEmail, String customerOtherDetails) {
        this.customerId = customerId;
        this.customerName = customerName;
        this.customerEmail = customerEmail;
        this.customerOtherDetails = customerOtherDetails;
    }
}
