// Copyright (c) 2022, 2026, Oracle and/or its affiliates.

package oracle.obaas.aznserver.controller;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Optional;
import java.util.regex.Pattern;

import lombok.extern.slf4j.Slf4j;
import oracle.obaas.aznserver.model.User;
import oracle.obaas.aznserver.model.UserRoles;
import oracle.obaas.aznserver.repository.UserRepository;
import org.apache.commons.lang3.StringUtils;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.context.SecurityContext;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/user/api/v1")
@Slf4j
public class DbUserRepoController {

    public static final String ROLE_ADMIN = "ADMIN";
    private static final String ADMIN_AUTHORIZATION = "hasRole('ADMIN')";
    private static final String USER_AUTHORIZATION = "hasRole('USER')";
    private static final String CONFIG_EDITOR_AUTHORIZATION = "hasRole('CONFIG_EDITOR')";
    private static final String CONNECT_AUTHORIZATION = "hasAnyRole('ADMIN','USER','CONFIG_EDITOR')";
    private static final Pattern PASSWORD_PATTERN =
            Pattern.compile("^(?=.*[?!$%^*\\-_])(?=.*[0-9])(?=.*[a-z])(?=.*[A-Z]).{12,}$");

    final UserRepository userRepository;
    final PasswordEncoder passwordEncoder;

    public DbUserRepoController(UserRepository userRepository, PasswordEncoder passwordEncoder) {
        this.userRepository = userRepository;
        this.passwordEncoder = passwordEncoder;
    }

    /**
     * Perform the connect operation, which forces authentication.
     * 
     * You can test this method with a command like this:
     * 
     * { @code curl -i -u obaas-admin:password
     * http://localhost:8080/user/api/v1/connect }
     * 
     * @return HTTP status code 200 (OK) if the authentication was successful and
     *         the user has
     *         the necessary roles, along with a list of the user's roles in the
     *         response body
     *         in this format: "[ROLE_USER, ROLE_ADMIN, ROLE_CONFIG_EDITOR]".
     */
    @PreAuthorize(CONNECT_AUTHORIZATION)
    @GetMapping("/connect")
    public ResponseEntity<String> connect() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        UserDetails userDetails = (UserDetails) authentication.getPrincipal();
        String authorities = userDetails.getAuthorities().toString();

        log.debug("/connect Username: {}", authentication.getName());
        log.debug("/connect Authorities: {}", userDetails.getAuthorities());
        log.debug("/connect Details: {}", authentication.getDetails());

        return new ResponseEntity<>(authorities, HttpStatus.OK);
    }

    /**
     * Find all users ontaining a username. If no param is provided
     * all users are returned.
     * 
     * You can test this method with a command like this:
     *
     * {@code curl -i -u obaas-admin:password  http://localhost:8080/user/api/v1/findUser }
     * {@code curl -i -u obaas-admin:password 'http://localhost:8080/user/api/v1/findUser?username=obaas-admin' }
     * 
     * @param username Optional username, if specified will search for usernames
     *                 that start with
     *                 this string, ignoring case.
     * @return A list of users that match the supplied username, if specified; or
     *         all users if no username is specified.
     */
    @PreAuthorize(ADMIN_AUTHORIZATION)
    @GetMapping("/findUser")
    public ResponseEntity<List<User>> getUsers(@RequestParam(required = false) String username) {

        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        UserDetails userDetails = (UserDetails) authentication.getPrincipal();
        log.debug("/findUser Authorities: {}", userDetails.getAuthorities());

        try {
            List<User> users = new ArrayList<>();
            if (username == null) {
                users.addAll(userRepository.findAll());
            } else {
                users.addAll(userRepository.findUsersByUsernameStartsWithIgnoreCase(username));
            }

            if (users.isEmpty()) {
                return new ResponseEntity<>(HttpStatus.NO_CONTENT);
            }
            return new ResponseEntity<>(users, HttpStatus.OK);

        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    /**
     * Create a new user.
     * 
     * You can test this method with a command like this:
     * 
     * {@code curl -u obaas-admin:'password'  -i -X POST \ }
     * {@code   -H 'Content-Type: application/json' \ }
     * {@code -d '{"username": "Nisse", "password": "howdy", "roles" : "USER_ROLE"}'
     * \ }
     * {@code -d '{"username": "Nisse", "password": "howdy", "roles" : "USER_ROLE",
     * "email" : "noreply@mydomain.com"}'
     * \ }
     * {@code   http://localhost:8080/user/api/v1/createUser }
     * 
     * @param user The new user.
     * @return The new user and HTTP status code 201 (created) if successful, 409 if
     *         user exists or 500 if problems.
     */
    @PreAuthorize(ADMIN_AUTHORIZATION)
    @PostMapping("/createUser")
    public ResponseEntity<?> createUser(@RequestBody User user) {

        // If user exists return HTTP Status 409.
        Optional<User> checkUser = userRepository.findByUsernameIgnoreCase(user.getUsername());
        if (checkUser.isPresent()) {
            log.debug("User exists");
            return new ResponseEntity<>("User already exists", HttpStatus.CONFLICT);
        }

        if (!isValidPassword(user.getPassword())) {
            return new ResponseEntity<>("Password does not meet complexity requirements",
                    HttpStatus.UNPROCESSABLE_CONTENT);
        }

        if (StringUtils.isNotEmpty(user.getEmail())) {
            Optional<User> userAlreadyAssociatedWithEMail = userRepository.findByEmailIgnoreCase(user.getEmail());
            if (userAlreadyAssociatedWithEMail.isPresent()) {
                log.debug("User exists");
                return new ResponseEntity<>("Another user exists with same email", HttpStatus.CONFLICT);
            }
        }

        // Validate roles in RequestBody
        boolean hasValidRole = validateRole(user);
        log.debug("Valid role: {}", hasValidRole);

        // If Valid role create the user else send HTTP 422
        if (hasValidRole) {
            try {
                User users = userRepository.save(new User(
                        user.getUsername(),
                        passwordEncoder.encode(user.getPassword()),
                        user.getRoles(), user.getEmail()));
                return new ResponseEntity<>(users, HttpStatus.CREATED);
            } catch (Exception e) {
                return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
            }
        } else {
            return ResponseEntity.status(HttpStatus.UNPROCESSABLE_CONTENT).build();
        }
    }

    /**
     * Change a user's password. An admin user can change anyone's password, a
     * regular user can only change its own password.
     * 
     * You can test this method with a command like this:
     *
     * {@code curl -u obaas-admin:password  -i -X PUT \ }
     * {@code   -H 'Content-Type: application/json' \ }
     * {@code -d '{"username": "obaas-admin", "password": "newpassword"}' \ }
     * {@code   http://localhost:8080/user/api/v1/updatePassword }
     *
     * @param userInfo The user object containing the username and new password.
     * @return HTTP status 200 (OK) if successful, 403 (Forbidden) if user does
     *         not have necessary permission, or 500 for other errors.
     */
    @PreAuthorize(USER_AUTHORIZATION)
    @PutMapping("/updatePassword")
    public ResponseEntity<User> changePassword(@RequestBody UserInfoDto userInfo) {

        if (!isValidPassword(userInfo.password())) {
            return ResponseEntity.status(HttpStatus.UNPROCESSABLE_CONTENT).build();
        }

        // Check if the user is a user with ADMIN
        SecurityContext securityContext = SecurityContextHolder.getContext();
        boolean isAdminUser = false;

        for (GrantedAuthority role : securityContext.getAuthentication().getAuthorities()) {
            if (role.getAuthority().contains(ROLE_ADMIN)) {
                isAdminUser = true;
            }
        }

        // TODO: Must update the correspondent secret??

        // If the username of the authenticated user matches the requestbody username,
        // or if it is a user with ROLE_ADMIN
        if ((userInfo.username().compareTo(securityContext.getAuthentication().getName()) == 0) || isAdminUser) {
            try {
                Optional<User> user = userRepository.findByUsername(userInfo.username());
                if (user.isPresent()) {
                    user.get().setPassword(passwordEncoder.encode(userInfo.password()));
                    userRepository.saveAndFlush(user.get());
                    return ResponseEntity.status(HttpStatus.OK).build();
                } else {
                    return ResponseEntity.status(HttpStatus.NO_CONTENT).build();
                }
            } catch (Exception e) {
                return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
            }
        } else {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
    }

    /**
     * Change a user's Roles. An admin user can change anyone's roles
     * Roles must be on ore more of:
     * ROLE_ADMIN, ROLE_USER, ROLE_CONFIG_EDITOR
     * 
     * You can test this method with a command like this:
     *
     * {@code curl -u obaas-admin:password  -i -X PUT \ }
     * {@code   -H 'Content-Type: application/json' \ }
     * {@code -d '{"username": "obaas-user", "roles": "ROLE_USER"}' \ }
     * {@code   http://localhost:8080/user/api/v1/updateRole }
     *
     * @param user The user object containing the username and new role(s).
     * @return HTTP status 200 (OK) if successful, 403 (Forbidden) if user does
     *         not have necessary permission, or 500 for other errors.
     */
    @PreAuthorize(ADMIN_AUTHORIZATION)
    @PutMapping("/changeRole")
    public ResponseEntity<User> updateRole(@RequestBody User user) {

        // Validate roles in RequestBody
        boolean hasValidRole = validateRole(user);
        log.debug("Valid role: {}", hasValidRole);

        // Only if the roles are valid
        if (hasValidRole) {
            try {
                Optional<User> userToUpdate = userRepository.findByUsernameIgnoreCase(user.getUsername());
                if (userToUpdate.isPresent()) {
                    log.debug("Before role update: {}", userToUpdate.get().getRoles());
                    log.debug("Requested role update: {}", user.getRoles());
                    userToUpdate.get().setRoles(user.getRoles());
                    userRepository.saveAndFlush(userToUpdate.get());
                    return ResponseEntity.status(HttpStatus.OK).build();
                } else {
                    return ResponseEntity.status(HttpStatus.NO_CONTENT).build();
                }
            } catch (Exception e) {
                return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
            }
        } else {
            return ResponseEntity.status(HttpStatus.UNPROCESSABLE_CONTENT).build();
        }
    }

    /**
     * Delete a user by username.
     * 
     * You can test this method with a command like this:
     * 
     * {@code curl -u obaas-admin:password -i -X DELETE http://localhost:8080/user/api/v1/deleteUsername/username=<username>}
     * 
     * @param username Required username, The username of the user to delete,
     *                 ignoring case
     * @return HTTP status code 200 (OK) if successful, or 500 otherwise.
     */
    @PreAuthorize(ADMIN_AUTHORIZATION)
    @DeleteMapping("/deleteUsername")
    public ResponseEntity<Void> deleteUserByUsername(@RequestParam(required = true) String username) {
        try {
            Optional<User> user = userRepository.findByUsernameIgnoreCase(username);

            if (user.isPresent()) {
                log.debug("Deleting user: {}", user.get().getUserId());
                userRepository.deleteById(user.get().getUserId());
                return new ResponseEntity<>(HttpStatus.OK);
            } else {
                return new ResponseEntity<>(HttpStatus.NO_CONTENT);
            }
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }

    }

    /**
     * Delete a user by id.
     * 
     * You can test this method with a command like this:
     * 
     * {@code curl -u obaas-admin:password -i -X DELETE http://localhost:8080/user/api/v1/deleteId/id=<id>> }
     * 
     * @param id Required id, The id of the user to delete.
     * @return HTTP status code 200 (OK) if successful, or 500 otherwise.
     */
    @PreAuthorize(ADMIN_AUTHORIZATION)
    @DeleteMapping("/deleteId")
    public ResponseEntity<Void> deleteUserById(@RequestParam(required = true) long id) {
        try {
            Optional<User> user = userRepository.findById(id);

            if (user.isPresent()) {
                userRepository.deleteById(id);
                return new ResponseEntity<>(HttpStatus.OK);
            } else {
                return new ResponseEntity<>(HttpStatus.NO_CONTENT);
            }
        } catch (Exception e) {
            return new ResponseEntity<>(HttpStatus.INTERNAL_SERVER_ERROR);
        }
    }

    /**
     * Test method to see if a user has ROLE_USER.
     * Method should return success message for ROLE_ADMIN.
     * 
     * @return String with success message
     */
    @PreAuthorize(USER_AUTHORIZATION)
    @GetMapping("/pinguser")
    public String pingSecureUser() {

        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        UserDetails userDetails = (UserDetails) authentication.getPrincipal();
        log.debug("/pinguser Authorities: {}", userDetails.getAuthorities());

        return "/pinguser : Secure User Ping Pong!";
    }

    /**
     * Test method to see if a user has ROLE_ADMIN.
     * 
     * @return String with success message
     */
    @PreAuthorize(ADMIN_AUTHORIZATION)
    @GetMapping("/pingadmin")
    public String pingSecureAdmin() {

        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        UserDetails userDetails = (UserDetails) authentication.getPrincipal();
        log.debug("/pingadmin Authorities: {}", userDetails.getAuthorities());

        return "/pingadmin : Secure Admin Ping Pong!";
    }

    /**
     * Test method to see if a user has ROLE_CONFIG_EDITOR.
     * Method should return success message for ROLE_ADMIN but not for ROLE_USER.
     * 
     * @return String with success message
     */
    @PreAuthorize(CONFIG_EDITOR_AUTHORIZATION)
    @GetMapping("/pingceditor")
    public String pingSecureContentEditor() {

        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        UserDetails userDetails = (UserDetails) authentication.getPrincipal();
        log.debug("/pingceditor Authorities: {}", userDetails.getAuthorities());

        return "/pingceditor : Secure Content Editor Soccer!";
    }

    /**
     * A test method with no authentication.
     * 
     * @return a test result.
     */
    @GetMapping("/ping")
    public String ping() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        log.debug("/ping Username: {}", authentication.getName());
        log.debug("/ping Authorities: {}", authentication.getAuthorities());
        log.debug("/ping Details: {}", authentication.getDetails());
        return "Ping Pong! no Authentication at all";
    }

    /**
     * Validate a User's role.
     * 
     * Roles must be one or more of
     * ROLE_ADMIN, ROLE_USER, ROLE_CONFIG_EDITOR
     * 
     * @return boolean if the user has valid roles or not
     */
    private boolean validateRole(User user) {
        try {
            if (StringUtils.isBlank(user.getRoles())) {
                return false;
            }
            Arrays.stream(user.getRoles().toUpperCase()
                    .replace("[", "")
                    .replace("]", "")
                    .replace(" ", "")
                    .split(","))
                    .map(UserRoles::valueOf)
                    .toList();
            return true;
        } catch (IllegalArgumentException illegalArgumentException) {
            return false;
        }
    }

    /**
     * Change a user's Email.
     * You can test this method with a command like this:
     *
     * {@code curl -u obaas-admin:password  -i -X PUT \ }
     * {@code   -H 'Content-Type: application/json' \ }
     * {@code -d '{"username": "obaas-user", "email": "noreply@mydomain.com"}' \ }
     * {@code   http://localhost:8080/user/api/v1/changeEmail }
     *
     * @param user The user object containing the username and new role(s).
     * @return HTTP status 200 (OK) if successful, 403 (Forbidden) if user does
     *         not have necessary permission, or 500 for other errors.
     */
    @PreAuthorize(ADMIN_AUTHORIZATION)
    @PutMapping("/changeEmail")
    public ResponseEntity<User> updateEmail(@RequestBody User user) {

        // Validate email in RequestBody
        boolean hasValidEmailOrIsBlank = StringUtils.isBlank(user.getEmail())
                || user.getEmail().matches("^(.+)@(\\S+)$");

        // Only if the email is valid
        if (hasValidEmailOrIsBlank) {
            try {
                if (StringUtils.isNotEmpty(user.getEmail())) {
                    Optional<User> userAlreadyAssociatedWithEMail = userRepository
                            .findByEmailIgnoreCase(user.getEmail());
                    if (userAlreadyAssociatedWithEMail.isPresent()
                            && !userAlreadyAssociatedWithEMail.get().getUsername().equals(user.getUsername())) {
                        log.debug("User exists");
                        return ResponseEntity.status(HttpStatus.CONFLICT).build();
                    }
                }

                Optional<User> userToUpdate = userRepository.findByUsernameIgnoreCase(user.getUsername());
                if (userToUpdate.isPresent()) {
                    log.debug("Before email update: {}", userToUpdate.get().getEmail());
                    log.debug("Requested email update: {}", user.getEmail());
                    userToUpdate.get().setEmail(user.getEmail());
                    userRepository.saveAndFlush(userToUpdate.get());
                    return ResponseEntity.status(HttpStatus.OK).build();
                } else {
                    return ResponseEntity.status(HttpStatus.NO_CONTENT).build();
                }
            } catch (Exception e) {
                return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
            }
        } else {
            return ResponseEntity.status(HttpStatus.UNPROCESSABLE_CONTENT).build();
        }
    }

    /**
     * Get username, email and one-time password for an user.
     * 
     * You can test this method with a command like this:
     *
     * {@code curl -X GET \ }
     * {@code -H 'Content-Type: application/json' \ }
     * {@code -d '{"username": "some-user"}' \ } or {@code -d '{"email":
     * "noreply@mydomain.com"}' \ }
     * {@code  http://localhost:8080/user/api/v1/forgot }
     * 
     * @param username - the username of the User
     * @param email    - the email of the User
     * @return A UserInfoDto object containing username and email
     *         for the user.
     */
    @PreAuthorize(ADMIN_AUTHORIZATION)
    @GetMapping("/forgot")
    public ResponseEntity<UserInfoDto> getUsernameEmailAndOTP(@RequestParam(required = false) String username,
            @RequestParam(required = false) String email) {
        try {
            Optional<User> user = Optional.empty();
            if (StringUtils.isNotEmpty(username)) {
                user = userRepository.findByUsernameIgnoreCase(username);
            } else if (StringUtils.isNotEmpty(email)) {
                user = userRepository.findByEmailIgnoreCase(email);
            }

            if (user.isEmpty()) {
                return new ResponseEntity<>(HttpStatus.NO_CONTENT);
            }

            return new ResponseEntity<>(
                    new UserInfoDto(user.get().getUsername(), null, user.get().getEmail()),
                    HttpStatus.OK);
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }

    }

    /**
     * Saves generated one-time password for an user.
     * 
     * You can test this method with a command like this:
     *
     * {@code curl -X POST \ }
     * {@code -H 'Content-Type: application/json' \ }
     * {@code -d '{"username": "some-user", "otp" : "some-otp"}' \ }
     * {@code  http://localhost:8080/user/api/v1/forgot }
     * 
     * @param inUser the User object containing username and generated one-time
     *               password.
     * @return HTTP status 200 (OK) if successful or 500/422 for other errors.
     */
    @PreAuthorize(ADMIN_AUTHORIZATION)
    @PostMapping("/forgot")
    public ResponseEntity<UserInfoDto> createOTP(@RequestBody(required = true) User inUser) {
        if (StringUtils.isNotEmpty(inUser.getUsername()) && StringUtils.isNotEmpty(inUser.getOtp())) {
            try {
                Optional<User> user = userRepository.findByUsernameIgnoreCase(inUser.getUsername());
                if (user.isEmpty()) {
                    return new ResponseEntity<>(HttpStatus.NO_CONTENT);
                }
                user.get().setOtp(passwordEncoder.encode(inUser.getOtp()));
                userRepository.saveAndFlush(user.get());
                return ResponseEntity.status(HttpStatus.OK).build();
            } catch (Exception e) {
                return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
            }

        } else {
            return ResponseEntity.status(HttpStatus.UNPROCESSABLE_CONTENT).build();
        }
    }

    /**
     * Saves generated one-time password for an user.
     * 
     * You can test this method with a command like this:
     *
     * {@code curl -X PUT \ }
     * {@code -H 'Content-Type: application/json' \ }
     * {@code -d '{"username": "some-user", "otp" : "some-otp", "password" :
     * "some-password"}' \ }
     * {@code  http://localhost:8080/user/api/v1/forgot }
     * 
     * @param inUser the User object containing username, one-time password and
     *               updated password.
     * @return HTTP status 200 (OK) if successful or 500/422/409 for other errors.
     */
    @PreAuthorize(ADMIN_AUTHORIZATION)
    @PutMapping("/forgot")
    public ResponseEntity<?> reset(@RequestBody(required = true) User inUser) {
        if (StringUtils.isNotEmpty(inUser.getUsername()) && StringUtils.isNotEmpty(inUser.getOtp())
                && StringUtils.isNotEmpty(inUser.getPassword())) {
            if (!isValidPassword(inUser.getPassword())) {
                return new ResponseEntity<>("Password does not meet complexity requirements",
                        HttpStatus.UNPROCESSABLE_CONTENT);
            }
            try {
                Optional<User> user = userRepository.findByUsernameIgnoreCase(inUser.getUsername());
                if (user.isEmpty()) {
                    return new ResponseEntity<>("User does not exist", HttpStatus.NO_CONTENT);
                }

                if (StringUtils.isEmpty(user.get().getOtp())) {
                    return new ResponseEntity<>("OTP not  generated.", HttpStatus.CONFLICT);
                }

                if (StringUtils.isEmpty(user.get().getPassword())) {
                    return new ResponseEntity<>("Password not  provided.", HttpStatus.CONFLICT);
                }

                if (!passwordEncoder.matches(inUser.getOtp(), user.get().getOtp())) {
                    return new ResponseEntity<>("OTP does not match.", HttpStatus.CONFLICT);
                }

                if (passwordEncoder.matches(inUser.getPassword(), user.get().getPassword())) {
                    return new ResponseEntity<>("Password can not be same as previous.", HttpStatus.CONFLICT);
                }

                user.get().setOtp(null);
                user.get().setPassword(passwordEncoder.encode(inUser.getPassword()));
                userRepository.saveAndFlush(user.get());

                return new ResponseEntity<>("Password successfully changed.",
                        HttpStatus.OK);
            } catch (Exception e) {
                return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
            }

        } else {
            return ResponseEntity.status(HttpStatus.UNPROCESSABLE_CONTENT).build();
        }
    }

    private boolean isValidPassword(String password) {
        return StringUtils.isNotBlank(password) && PASSWORD_PATTERN.matcher(password).matches();
    }
}
