// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/
package com.example;

import java.util.Date;
import org.hibernate.annotations.CreationTimestamp;
import jakarta.persistence.Access;
import jakarta.persistence.AccessType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.NamedQueries;
import jakarta.persistence.NamedQuery;
import jakarta.persistence.Table;

@Entity
@Table(name = "CUSTOMER")
@Access(AccessType.PROPERTY)
@NamedQueries({
    @NamedQuery(name = "getCustomers",
                query = "SELECT c FROM Customer c"),
    @NamedQuery(name = "getCustomerById",
                query = "SELECT c FROM Customer c WHERE c.customerId = :id"),
    @NamedQuery(name = "getCustomerByCustomerNameContaining",
                query = "SELECT c FROM Customer c WHERE c.customerName LIKE :customerName"),
    @NamedQuery(name = "getCustomerByCustomerEmailContaining",
                query = "SELECT c FROM Customer c WHERE c.customerEmail LIKE :customerEmail")
})
public class Customer {
    
    private String customerId;
    private String customerName;
    private String customerEmail;
    private Date dateBecameCustomer;
    private String customerOtherDetails;
    private String customerPassword;
    
    // Default constructor required by JPA
    public Customer() {}
    
    /**
     * Creates a Customer object.
     * @param customerId The Customer ID
     * @param customerName The Customer Name
     * @param customerEmail The Customer Email
     * @param customerOtherDetails Other details about the customer
     */
    public Customer(String customerId, String customerName, String customerEmail, String customerOtherDetails) {
        this.customerId = customerId;
        this.customerName = customerName;
        this.customerEmail = customerEmail;
        this.customerOtherDetails = customerOtherDetails;
    }
    
    /**
     * Full constructor including password
     * @param customerId The Customer ID
     * @param customerName The Customer Name
     * @param customerEmail The Customer Email
     * @param customerOtherDetails Other details about the customer
     * @param customerPassword The Customer Password
     */
    public Customer(String customerId, String customerName, String customerEmail, 
                   String customerOtherDetails, String customerPassword) {
        this.customerId = customerId;
        this.customerName = customerName;
        this.customerEmail = customerEmail;
        this.customerOtherDetails = customerOtherDetails;
        this.customerPassword = customerPassword;
    }
    
    @Id
    @Column(name = "CUSTOMER_ID", nullable = false, updatable = false)
    public String getCustomerId() {
        return customerId;
    }
    
    public void setCustomerId(String customerId) {
        this.customerId = customerId;
    }
    
    @Column(name = "CUSTOMER_NAME")
    public String getCustomerName() {
        return customerName;
    }
    
    public void setCustomerName(String customerName) {
        this.customerName = customerName;
    }
    
    @Column(name = "CUSTOMER_EMAIL")
    public String getCustomerEmail() {
        return customerEmail;
    }
    
    public void setCustomerEmail(String customerEmail) {
        this.customerEmail = customerEmail;
    }
    
    @CreationTimestamp
    @Column(name = "DATE_BECAME_CUSTOMER", updatable = false, insertable = false)
    public Date getDateBecameCustomer() {
        return dateBecameCustomer;
    }
    
    public void setDateBecameCustomer(Date dateBecameCustomer) {
        this.dateBecameCustomer = dateBecameCustomer;
    }
    
    @Column(name = "CUSTOMER_OTHER_DETAILS")
    public String getCustomerOtherDetails() {
        return customerOtherDetails;
    }
    
    public void setCustomerOtherDetails(String customerOtherDetails) {
        this.customerOtherDetails = customerOtherDetails;
    }
    
    @Column(name = "PASSWORD")
    public String getCustomerPassword() {
        return customerPassword;
    }
    
    public void setCustomerPassword(String customerPassword) {
        this.customerPassword = customerPassword;
    }
    
    @Override
    public String toString() {
        return "Customer{" +
               "customerId='" + customerId + '\'' +
               ", customerName='" + customerName + '\'' +
               ", customerEmail='" + customerEmail + '\'' +
               ", dateBecameCustomer=" + dateBecameCustomer +
               ", customerOtherDetails='" + customerOtherDetails + '\'' +
               '}';
    }
    
    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        Customer customer = (Customer) o;
        return customerId != null ? customerId.equals(customer.customerId) : customer.customerId == null;
    }
    
    @Override
    public int hashCode() {
        return customerId != null ? customerId.hashCode() : 0;
    }
}