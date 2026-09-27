// Copyright (c) 2023, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

package com.example.accounts.controller;

import java.net.URI;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import com.example.accounts.model.Account;
import com.example.accounts.model.Journal;
import com.example.accounts.repository.AccountRepository;
import com.example.accounts.repository.JournalRepository;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

import static com.example.common.security.CloudBankAuthorization.canAccessCustomer;
import static com.example.common.security.CloudBankAuthorization.isPrivileged;

@RestController
@RequestMapping("/api/v1")
public class AccountController {

    final AccountRepository accountRepository;
    final JournalRepository journalRepository;

    public AccountController(AccountRepository accountRepository, JournalRepository journalRepository) {
        this.accountRepository = accountRepository;
        this.journalRepository = journalRepository;
    }

    /**
     * Get all Accounts.
     *
     * @return List off accounts
     */
    @GetMapping("/accounts")
    public List<Account> getAllAccounts(Authentication authentication) {
        if (!isPrivileged(authentication)) {
            if (authentication == null || authentication.getName() == null) {
                return List.of();
            }
            return accountRepository.findByAccountCustomerId(authentication.getName());
        }
        return accountRepository.findAll();
    }

    /**
     * Create an account.
     *
     * @param account Account object.
     * @return Returns HTTP Status code or the URI of the created object.
     */
    @PostMapping("/account")
    public ResponseEntity<Account> createAccount(@RequestBody Account account, Authentication authentication) {
        if (!canAccessCustomer(authentication, account.getAccountCustomerId())) {
            return new ResponseEntity<>(HttpStatus.FORBIDDEN);
        }
        boolean exists = accountRepository.existsById(account.getAccountId());

        if (!exists) {
            try {
                Account newAccount = accountRepository.saveAndFlush(account);
                URI location = ServletUriComponentsBuilder
                        .fromCurrentRequest()
                        .path("/{id}")
                        .buildAndExpand(newAccount.getAccountId())
                        .toUri();
                return ResponseEntity.created(location).build();
            } catch (Exception e) {
                return new ResponseEntity<>(account, HttpStatus.INTERNAL_SERVER_ERROR);
            }
        } else {
            return new ResponseEntity<>(account, HttpStatus.CONFLICT);
        }
    }

    /**
     * Find an account by Account Id.
     *
     * @param accountId Account Id
     * @return An account
     */
    @GetMapping("/account/{accountId}")
    public ResponseEntity<Account> getAccountById(@PathVariable("accountId") long accountId,
            Authentication authentication) {
        Optional<Account> accountData = accountRepository.findById(accountId);
        try {
            return accountData.map(account -> accountResponse(account, authentication))
                    .orElseGet(() -> new ResponseEntity<>(HttpStatus.NOT_FOUND));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * Find an account by customer Id.
     *
     * @param customerId Customer Id
     * @return A list opf Account(s)
     */
    @GetMapping("/account/getAccounts/{customerId}")
    public ResponseEntity<List<Account>> getAccountsByCustomerId(@PathVariable("customerId") String customerId,
            Authentication authentication) {
        if (!canAccessCustomer(authentication, customerId)) {
            return new ResponseEntity<>(HttpStatus.FORBIDDEN);
        }
        try {
            List<Account> accountData = new ArrayList<Account>();
            accountData.addAll(accountRepository.findByAccountCustomerId(customerId));
            if (accountData.isEmpty()) {
                return new ResponseEntity<>(HttpStatus.NO_CONTENT);
            }
            return new ResponseEntity<>(accountData, HttpStatus.OK);
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * Delete an Account with specific Id.
     *
     * @param accountId Account ID
     * @return HTTP Status Code
     */
    @DeleteMapping("/account/{accountId}")
    public ResponseEntity<HttpStatus> deleteAccount(@PathVariable("accountId") long accountId) {
        try {
            accountRepository.deleteById(accountId);
            return new ResponseEntity<>(HttpStatus.NO_CONTENT);
        } catch (Exception e) {
            return new ResponseEntity<>(HttpStatus.INTERNAL_SERVER_ERROR);
        }
    }

    /**
     * Get transactions (Journal) for an Account Id.
     *
     * @param accountId Account Id
     * @return List of Journal object(s)
     */
    @GetMapping("/account/{accountId}/transactions")
    public ResponseEntity<List<Journal>> getTransactions(@PathVariable("accountId") long accountId,
            Authentication authentication) {
        ResponseEntity<HttpStatus> authorization = authorizeAccountAccess(accountId, authentication);
        if (authorization != null) {
            return new ResponseEntity<>(authorization.getStatusCode());
        }
        try {
            List<Journal> transactions = new ArrayList<Journal>();
            transactions.addAll(journalRepository.findByAccountId(accountId));
            if (transactions.isEmpty()) {
                return new ResponseEntity<>(HttpStatus.NO_CONTENT);
            }
            return new ResponseEntity<>(transactions, HttpStatus.OK);
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * Create a Journal entry.
     *
     * @param journalEntry Journal object
     * @return HTTP Status Code
     */
    @PostMapping("/account/journal")
    public ResponseEntity<Journal> postSimpleJournalEntry(@RequestBody Journal journalEntry,
            Authentication authentication) {
        ResponseEntity<HttpStatus> authorization = authorizeAccountAccess(journalEntry.getAccountId(), authentication);
        if (authorization != null) {
            return new ResponseEntity<>(authorization.getStatusCode());
        }
        boolean exists = journalRepository.existsById(journalEntry.getJournalId());
        if (!exists) {
            try {
                Journal newJournalEntry = journalRepository.saveAndFlush(journalEntry);
                return new ResponseEntity<>(newJournalEntry, HttpStatus.CREATED);
            } catch (Exception e) {
                return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
            }
        } else {
            return new ResponseEntity<>(journalEntry, HttpStatus.CONFLICT);
        }
    }

    /**
     * Find Journal entries by Account Id.
     *
     * @param accountId Account Id
     * @return Journal object(s)
     */
    @GetMapping("/account/{accountId}/journal")
    public ResponseEntity<List<Journal>> getJournalEntriesForAccount(@PathVariable("accountId") long accountId,
            Authentication authentication) {
        ResponseEntity<HttpStatus> authorization = authorizeAccountAccess(accountId, authentication);
        if (authorization != null) {
            return new ResponseEntity<>(authorization.getStatusCode());
        }
        return new ResponseEntity<>(journalRepository.findJournalByAccountId(accountId), HttpStatus.OK);
    }

    /**
     * Clears the Journal Entry.
     *
     * @param journalId Journal Id
     * @return HTTP Status Code
     */
    @PostMapping("/account/journal/{journalId}/clear")
    public ResponseEntity<Journal> clearJournalEntry(@PathVariable long journalId, Authentication authentication) {
        try {
            Optional<Journal> data = journalRepository.findById(journalId);
            if (data.isPresent()) {
                Journal newJournalEntry = data.get();
                ResponseEntity<HttpStatus> authorization =
                        authorizeAccountAccess(newJournalEntry.getAccountId(), authentication);
                if (authorization != null) {
                    return new ResponseEntity<>(authorization.getStatusCode());
                }
                newJournalEntry.setJournalType("DEPOSIT");
                journalRepository.saveAndFlush(newJournalEntry);
                return new ResponseEntity<Journal>(newJournalEntry, HttpStatus.OK);
            } else {
                return new ResponseEntity<Journal>(new Journal(), HttpStatus.ACCEPTED);
            }
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    private ResponseEntity<Account> accountResponse(Account account, Authentication authentication) {
        if (!canAccessCustomer(authentication, account.getAccountCustomerId())) {
            return new ResponseEntity<>(HttpStatus.FORBIDDEN);
        }
        return new ResponseEntity<>(account, HttpStatus.OK);
    }

    private ResponseEntity<HttpStatus> authorizeAccountAccess(long accountId, Authentication authentication) {
        Optional<Account> accountData = accountRepository.findById(accountId);
        if (accountData.isEmpty()) {
            return new ResponseEntity<>(HttpStatus.NOT_FOUND);
        }
        if (!canAccessCustomer(authentication, accountData.get().getAccountCustomerId())) {
            return new ResponseEntity<>(HttpStatus.FORBIDDEN);
        }
        return null;
    }

}
