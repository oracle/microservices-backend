// Copyright (c) 2022, 2023, Oracle and/or its affiliates.

package com.cloudbank.aznserver.repository;

import java.util.List;
import java.util.Optional;

import com.cloudbank.aznserver.model.User;
import org.springframework.data.jpa.repository.JpaRepository;

public interface UserRepository extends JpaRepository<User, Long> {

    Optional<User> findByUsername(String username);

    Optional<User> findByUsernameIgnoreCase(String username);

    Optional<User> findByUserId(Long userId);

    List<User> findUsersByUsernameStartsWithIgnoreCase(String username);

    Optional<User> findByEmailIgnoreCase(String email);

}
