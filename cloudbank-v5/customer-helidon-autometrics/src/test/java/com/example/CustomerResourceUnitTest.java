package com.example;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import jakarta.persistence.EntityManager;
import jakarta.persistence.TypedQuery;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.core.UriInfo;

import java.util.Arrays;
import java.util.List;
import java.util.Collections;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/**
 * Unit tests for CustomerResource using Mockito
 * These tests run without any containers or databases
 */
@ExtendWith(MockitoExtension.class)
public class CustomerResourceUnitTest {

    @Mock
    private EntityManager entityManager;

    @Mock
    private UriInfo uriInfo;

    @Mock
    private TypedQuery<Customer> typedQuery;

    @InjectMocks
    private CustomerResource customerResource;

    private Customer testCustomer;
    private List<Customer> testCustomers;

    @BeforeEach
    void setUp() {
        // Create test data
        testCustomer = new Customer("CUST001", "John Doe", "john.doe@example.com", "Premium customer");
        
        Customer customer2 = new Customer("CUST002", "Jane Smith", "jane.smith@gmail.com", "Standard customer");
        Customer customer3 = new Customer("CUST003", "Bob Johnson", "bob.johnson@yahoo.com", "VIP customer");
        
        testCustomers = Arrays.asList(testCustomer, customer2, customer3);
    }

    // ==============================================
    // GET ALL CUSTOMERS TESTS
    // ==============================================

    @Test
    @DisplayName("Should get all customers successfully")
    void testGetAllCustomers_Success() {
        // Arrange
        when(entityManager.createNamedQuery("getCustomers", Customer.class)).thenReturn(typedQuery);
        when(typedQuery.getResultList()).thenReturn(testCustomers);

        // Act
        Response response = customerResource.getCustomers();

        // Assert
        assertEquals(Response.Status.OK.getStatusCode(), response.getStatus());
        assertEquals(testCustomers, response.getEntity());
        
        verify(entityManager).createNamedQuery("getCustomers", Customer.class);
        verify(typedQuery).getResultList();
    }

    @Test
    @DisplayName("Should handle exception when getting all customers")
    void testGetAllCustomers_Exception() {
        // Arrange
        when(entityManager.createNamedQuery("getCustomers", Customer.class))
            .thenThrow(new RuntimeException("Database error"));

        // Act
        Response response = customerResource.getCustomers();

        // Assert
        assertEquals(Response.Status.INTERNAL_SERVER_ERROR.getStatusCode(), response.getStatus());
    }

    @Test
    @DisplayName("Should return empty list when no customers exist")
    void testGetAllCustomers_EmptyList() {
        // Arrange
        when(entityManager.createNamedQuery("getCustomers", Customer.class)).thenReturn(typedQuery);
        when(typedQuery.getResultList()).thenReturn(Collections.emptyList());

        // Act
        Response response = customerResource.getCustomers();

        // Assert
        assertEquals(Response.Status.OK.getStatusCode(), response.getStatus());
        assertEquals(Collections.emptyList(), response.getEntity());
    }

    // ==============================================
    // GET CUSTOMER BY ID TESTS
    // ==============================================

    @Test
    @DisplayName("Should get customer by ID successfully")
    void testGetCustomerById_Success() {
        // Arrange
        String customerId = "CUST001";
        when(entityManager.find(Customer.class, customerId)).thenReturn(testCustomer);

        // Act
        Response response = customerResource.getCustomerById(customerId);

        // Assert
        assertEquals(Response.Status.OK.getStatusCode(), response.getStatus());
        assertEquals(testCustomer, response.getEntity());
        
        verify(entityManager).find(Customer.class, customerId);
    }

    @Test
    @DisplayName("Should return 404 when customer not found by ID")
    void testGetCustomerById_NotFound() {
        // Arrange
        String customerId = "NONEXISTENT";
        when(entityManager.find(Customer.class, customerId)).thenReturn(null);

        // Act
        Response response = customerResource.getCustomerById(customerId);

        // Assert
        assertEquals(Response.Status.NOT_FOUND.getStatusCode(), response.getStatus());
        assertNull(response.getEntity());
    }

    @Test
    @DisplayName("Should handle exception when getting customer by ID")
    void testGetCustomerById_Exception() {
        // Arrange
        String customerId = "CUST001";
        when(entityManager.find(Customer.class, customerId))
            .thenThrow(new RuntimeException("Database error"));

        // Act
        Response response = customerResource.getCustomerById(customerId);

        // Assert
        assertEquals(Response.Status.INTERNAL_SERVER_ERROR.getStatusCode(), response.getStatus());
    }

    // ==============================================
    // SEARCH BY NAME TESTS
    // ==============================================

    @Test
    @DisplayName("Should search customers by name successfully")
    void testGetCustomerByName_Success() {
        // Arrange
        String searchName = "John";
        when(entityManager.createNamedQuery("getCustomerByCustomerNameContaining", Customer.class))
            .thenReturn(typedQuery);
        when(typedQuery.getResultList()).thenReturn(Arrays.asList(testCustomer));

        // Act
        Response response = customerResource.getCustomerByName(searchName);

        // Assert
        assertEquals(Response.Status.OK.getStatusCode(), response.getStatus());
        assertEquals(Arrays.asList(testCustomer), response.getEntity());
        
        verify(typedQuery).setParameter("customerName", "%" + searchName + "%");
    }

    @Test
    @DisplayName("Should return empty list when no customers match name")
    void testGetCustomerByName_NoMatches() {
        // Arrange
        String searchName = "NonExistent";
        when(entityManager.createNamedQuery("getCustomerByCustomerNameContaining", Customer.class))
            .thenReturn(typedQuery);
        when(typedQuery.getResultList()).thenReturn(Collections.emptyList());

        // Act
        Response response = customerResource.getCustomerByName(searchName);

        // Assert
        assertEquals(Response.Status.OK.getStatusCode(), response.getStatus());
        assertEquals(Collections.emptyList(), response.getEntity());
    }

    // ==============================================
    // SEARCH BY EMAIL TESTS
    // ==============================================

    @Test
    @DisplayName("Should search customers by email successfully")
    void testGetCustomerByEmail_Success() {
        // Arrange
        String searchEmail = "gmail";
        Customer gmailCustomer = new Customer("CUST002", "Jane Smith", "jane.smith@gmail.com", "Standard customer");
        
        when(entityManager.createNamedQuery("getCustomerByCustomerEmailContaining", Customer.class))
            .thenReturn(typedQuery);
        when(typedQuery.getResultList()).thenReturn(Arrays.asList(gmailCustomer));

        // Act
        Response response = customerResource.getCustomerByEmail(searchEmail);

        // Assert
        assertEquals(Response.Status.OK.getStatusCode(), response.getStatus());
        assertEquals(Arrays.asList(gmailCustomer), response.getEntity());
        
        verify(typedQuery).setParameter("customerEmail", "%" + searchEmail + "%");
    }

    // ==============================================
    // CREATE CUSTOMER TESTS
    // ==============================================

    @Test
    @DisplayName("Should create customer successfully")
    void testCreateCustomer_Success() {
        // Arrange
        Customer newCustomer = new Customer("CUST004", "New Customer", "new@example.com", "Details");
        when(entityManager.find(Customer.class, newCustomer.getCustomerId())).thenReturn(null);

        // Act
        Response response = customerResource.createCustomer(newCustomer);

        // Assert
        assertEquals(Response.Status.CREATED.getStatusCode(), response.getStatus());
        
        verify(entityManager).persist(newCustomer);
        verify(entityManager).flush();
    }

    @Test
    @DisplayName("Should return conflict when customer already exists")
    void testCreateCustomer_Conflict() {
        // Arrange
        when(entityManager.find(Customer.class, testCustomer.getCustomerId())).thenReturn(testCustomer);

        // Act
        Response response = customerResource.createCustomer(testCustomer);

        // Assert
        assertEquals(Response.Status.CONFLICT.getStatusCode(), response.getStatus());
        assertEquals(testCustomer, response.getEntity());
        
        verify(entityManager, never()).persist(any());
    }

    @Test
    @DisplayName("Should handle exception when creating customer")
    void testCreateCustomer_Exception() {
        // Arrange
        Customer newCustomer = new Customer("CUST004", "New Customer", "new@example.com", "Details");
        when(entityManager.find(Customer.class, newCustomer.getCustomerId())).thenReturn(null);
        doThrow(new RuntimeException("Database error")).when(entityManager).persist(newCustomer);

        // Act
        Response response = customerResource.createCustomer(newCustomer);

        // Assert
        assertEquals(Response.Status.INTERNAL_SERVER_ERROR.getStatusCode(), response.getStatus());
    }

    // ==============================================
    // UPDATE CUSTOMER TESTS
    // ==============================================

    @Test
    @DisplayName("Should update customer successfully")
    void testUpdateCustomer_Success() {
        // Arrange
        String customerId = "CUST001";
        Customer updatedData = new Customer(customerId, "John Doe Updated", "john.updated@example.com", "Updated details");
        Customer existingCustomer = new Customer(customerId, "John Doe", "john.doe@example.com", "Original details");
        
        when(entityManager.find(Customer.class, customerId)).thenReturn(existingCustomer);
        when(entityManager.merge(existingCustomer)).thenReturn(existingCustomer);

        // Act
        Response response = customerResource.updateCustomer(customerId, updatedData);

        // Assert
        assertEquals(Response.Status.OK.getStatusCode(), response.getStatus());
        assertEquals(existingCustomer, response.getEntity());
        
        // Verify the customer was updated with new values
        assertEquals("John Doe Updated", existingCustomer.getCustomerName());
        assertEquals("john.updated@example.com", existingCustomer.getCustomerEmail());
        assertEquals("Updated details", existingCustomer.getCustomerOtherDetails());
        
        verify(entityManager).merge(existingCustomer);
    }

    @Test
    @DisplayName("Should return 404 when updating non-existent customer")
    void testUpdateCustomer_NotFound() {
        // Arrange
        String customerId = "NONEXISTENT";
        Customer updatedData = new Customer(customerId, "Updated Name", "updated@example.com", "Updated details");
        
        when(entityManager.find(Customer.class, customerId)).thenReturn(null);

        // Act
        Response response = customerResource.updateCustomer(customerId, updatedData);

        // Assert
        assertEquals(Response.Status.NOT_FOUND.getStatusCode(), response.getStatus());
        
        verify(entityManager, never()).merge(any());
    }

    // ==============================================
    // DELETE CUSTOMER TESTS
    // ==============================================

    @Test
    @DisplayName("Should delete customer successfully")
    void testDeleteCustomer_Success() {
        // Arrange
        String customerId = "CUST001";
        when(entityManager.find(Customer.class, customerId)).thenReturn(testCustomer);

        // Act
        Response response = customerResource.deleteCustomer(customerId);

        // Assert
        assertEquals(Response.Status.NO_CONTENT.getStatusCode(), response.getStatus());
        
        verify(entityManager).remove(testCustomer);
    }

    @Test
    @DisplayName("Should return 404 when deleting non-existent customer")
    void testDeleteCustomer_NotFound() {
        // Arrange
        String customerId = "NONEXISTENT";
        when(entityManager.find(Customer.class, customerId)).thenReturn(null);

        // Act
        Response response = customerResource.deleteCustomer(customerId);

        // Assert
        assertEquals(Response.Status.NOT_FOUND.getStatusCode(), response.getStatus());
        
        verify(entityManager, never()).remove(any());
    }

    // ==============================================
    // LOAN APPLICATION TESTS
    // ==============================================

    @Test
    @DisplayName("Should return 418 for loan application")
    void testApplyForLoan_TeapotResponse() {
        // Arrange
        long loanAmount = 10000L;

        // Act
        Response response = customerResource.applyForLoan(loanAmount);

        // Assert
        assertEquals(418, response.getStatus()); // I'm a Teapot
    }

    @Test
    @DisplayName("Should handle different loan amounts")
    void testApplyForLoan_DifferentAmounts() {
        // Test multiple loan amounts
        long[] amounts = {1000L, 50000L, 100000L};
        
        for (long amount : amounts) {
            Response response = customerResource.applyForLoan(amount);
            assertEquals(418, response.getStatus());
        }
    }

    // ==============================================
    // CUSTOMER ENTITY TESTS
    // ==============================================

    @Test
    @DisplayName("Should create customer with all constructors")
    void testCustomerConstructors() {
        // Test default constructor
        Customer customer1 = new Customer();
        assertNull(customer1.getCustomerId());

        // Test 4-parameter constructor
        Customer customer2 = new Customer("ID", "Name", "email@test.com", "Details");
        assertEquals("ID", customer2.getCustomerId());
        assertEquals("Name", customer2.getCustomerName());
        assertEquals("email@test.com", customer2.getCustomerEmail());
        assertEquals("Details", customer2.getCustomerOtherDetails());

        // Test 5-parameter constructor
        Customer customer3 = new Customer("ID", "Name", "email@test.com", "Details", "password");
        assertEquals("password", customer3.getCustomerPassword());
    }

    @Test
    @DisplayName("Should test customer equals and hashCode")
    void testCustomerEqualsAndHashCode() {
        Customer customer1 = new Customer("CUST001", "John", "john@test.com", "Details");
        Customer customer2 = new Customer("CUST001", "Jane", "jane@test.com", "Other details");
        Customer customer3 = new Customer("CUST002", "John", "john@test.com", "Details");

        // Same ID should be equal
        assertEquals(customer1, customer2);
        assertEquals(customer1.hashCode(), customer2.hashCode());

        // Different ID should not be equal
        assertNotEquals(customer1, customer3);

        // toString should not contain password
        assertFalse(customer1.toString().contains("password"));
    }
}