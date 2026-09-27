// Copyright (c) 2023, Oracle and/or its affiliates.

package oracle.obaas.aznserver.controller;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import oracle.obaas.aznserver.model.User;
import oracle.obaas.aznserver.repository.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;
import tools.jackson.databind.ObjectMapper;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultHandlers.print;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(value = DbUserRepoController.class, properties = "azn.bootstrap-users.enabled=false")
@Import(TestSecurityConfig.class)
class AznServerApplicationTests {

    private static final String TEST_PASSWORD = "StrongerPass123!";

    @Autowired
    private ObjectMapper objectMapper;

    @MockitoBean
    UserRepository userRepository;

    private MockMvc mockMvc;

    @BeforeEach
    public void setup(WebApplicationContext webApplicationContext) {
        this.mockMvc = MockMvcBuilders.webAppContextSetup(webApplicationContext)
                .apply(springSecurity())
                .build();
    }

    @Test
    @WithMockUser(username = "obaas-user", password = "password", roles = { "USER" })
    void asObaasUser_shouldReturnOkAndRoleUser() throws Exception {
        mockMvc.perform(
                get("/user/api/v1/connect"))
                .andExpect(status().isOk())
                .andExpect(content().string("[ROLE_USER]"))
                .andDo(print());
    }

    @Test
    @WithMockUser(username = "obaas-admin", password = "password", roles = { "USER", "ADMIN" })
    void asObaasAdmin_shouldCreateUser() throws Exception {
        mockMvc.perform(
                post("/user/api/v1/createUser")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of(
                                "username", "andyadmin",
                                "password", TEST_PASSWORD,
                                "roles", "ROLE_USER"))))
                .andExpect(status().isCreated())
                .andDo(print());
    }

    @Test
    @WithMockUser(username = "obaas-admin", password = "password", roles = { "ADMIN" })
    void asObaasAdmin_shouldNotCreateUserWrongRole() throws Exception {

        User user = new User(
                "andyuser", TEST_PASSWORD, "WRONG_ROLE");

        mockMvc.perform(
                post("/user/api/v1/createUser")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(user)))
                .andExpect(status().is4xxClientError())
                .andDo(print());
    }

    @Test
    @WithMockUser(username = "obaas-admin", password = "password", roles = { "ADMIN" })
    void asObaasAdmin_shouldNotChangeRoleWrongRole() throws Exception {
        User user = new User(
                "andyuser", TEST_PASSWORD, "WRONG_ROLE");
        mockMvc.perform(
                put("/user/api/v1/changeRole")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(user)))
                .andExpect(status().is4xxClientError())
                .andDo(print());
    }

    @Test
    @WithMockUser(username = "obaas-user", password = "password", roles = { "USER" })
    void asObaasAdmin_shouldNotChangeRoleWrongPrivs() throws Exception {
        User user = new User(
                "andyuser", TEST_PASSWORD, "ROLE_USER");
        mockMvc.perform(
                put("/user/api/v1/changeRole")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(user)))
                .andExpect(status().isForbidden())
                .andDo(print());
    }

    @Test
    @WithMockUser(username = "obaas-admin", password = "password", roles = { "ADMIN" })
    void asObaasAdmin_shouldChangeRole() throws Exception {

        String username = "obaas-user";
        User user = new User("obaas-user", "password", "ROLE_USER");
        User updatedUser = new User("obaas-user", "password", "ROLE_CONFIG_EDITOR");

        when(userRepository.findByUsernameIgnoreCase(username)).thenReturn(Optional.of(user));
        when(userRepository.saveAndFlush(any(User.class))).thenReturn(updatedUser);

        mockMvc.perform(
                put("/user/api/v1/changeRole")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(updatedUser)))
                .andExpect(status().isOk())
                .andDo(print());
    }

    @Test
    @WithMockUser(username = "obaas-user", password = "password", roles = { "USER" })
    void asObaasUser_shouldNotCreateUser() throws Exception {
        User user = new User(
                "andyuser", "password", "ROLE_USER");

        mockMvc.perform(
                post("/user/api/v1/createUser")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(user)))
                .andExpect(status().isForbidden())
                .andDo(print());
    }

    @Test
    @WithMockUser(username = "obaas-admin", password = "password", roles = { "USER", "ADMIN" })
    void asObaasAdmin_findObaasAdminUser() throws Exception {

        String username = "obaas-admin";

        List<User> listOfUsers = 
                Arrays.asList(
                        new User(1,"obaas-admin", "password", "ROLE_ADMIN"),
                        new User(2,"obaas-user", "password", "ROLE_USER"),
                        new User(3,"config-user", "password", "ROLE_CONFIG_EDITOR"));

        List<User> filteredList = listOfUsers.stream().filter(p -> p.getUsername().contains(username)).toList();

        when(userRepository.findUsersByUsernameStartsWithIgnoreCase(username)).thenReturn(filteredList);

        mockMvc.perform(
                get("/user/api/v1/findUser").param("username", username))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.size()").value(1))
                .andDo(print());
    }

    @Test
    @WithMockUser(username = "obaas-admin", password = "password", roles = { "USER", "ADMIN" })
    void asObaasAdmin_findObaasUserUser() throws Exception {

        String username = "obaas-user";

        List<User> listOfUsers = new ArrayList<>(
                Arrays.asList(
                        new User(1,"obaas-admin", "password", "ROLE_ADMIN"),
                        new User(2,"obaas-user", "password", "ROLE_USER"),
                        new User(3,"config-user", "password", "ROLE_CONFIG_EDITOR")));

        List<User> filteredList = listOfUsers.stream().filter(p -> p.getUsername().contains(username)).toList();

        when(userRepository.findUsersByUsernameStartsWithIgnoreCase(username)).thenReturn(filteredList);

        mockMvc.perform(
                get("/user/api/v1/findUser").param("username", username))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.size()").value(filteredList.size()))
                .andDo(print());
    }

    @Test
    @WithMockUser(username = "bad-user", password = "password", roles = {})
    void asUserWithoutCorrectRole_shouldReturnForbidden() throws Exception {
        mockMvc.perform(
                get("/user/api/v1/connect"))
                .andExpect(status().isForbidden())
                .andDo(print());
    }

    @Test
    void asAnonymousUser_shouldReturnUnauthorized() throws Exception {
        mockMvc.perform(
                get("/user/api/v1/connect"))
                .andExpect(status().isUnauthorized())
                .andDo(print());
    }

    @Test
    @WithMockUser(username = "obaas-user", password = "password", roles = { "USER" })
    void asObaasUser_shouldReturnOkAndRoleUserPing() throws Exception {
        mockMvc.perform(
                get("/user/api/v1/connect"))
                .andExpect(status().isOk())
                .andExpect(content().string("[ROLE_USER]"))
                .andDo(print());
    }

    @Test
    @WithMockUser(username = "obaas-admin", password = "password", roles = { "ADMIN" })
    void asAObaasAdmin_shouldReturnOKPingAdmin() throws Exception {
        mockMvc.perform(
                get("/user/api/v1/pingadmin"))
                .andExpect(status().isOk())
                .andExpect(content().string("/pingadmin : Secure Admin Ping Pong!"))
                .andDo(print());
    }

    @Test
    @WithMockUser(username = "obaas-admin", password = "password", roles = { "ADMIN" })
    void asAObaasAdmin_shouldReturnOKPingUser() throws Exception {
        mockMvc.perform(
                get("/user/api/v1/pinguser"))
                .andExpect(status().isOk())
                .andExpect(content().string("/pinguser : Secure User Ping Pong!"))
                .andDo(print());
    }

    @Test
    @WithMockUser(username = "obaas-user", password = "password", roles = { "USER" })
    void asAObaasUser_shouldReturnOKPingAdmin() throws Exception {
        mockMvc.perform(
                get("/user/api/v1/pinguser"))
                .andExpect(status().isOk())
                .andExpect(content().string("/pinguser : Secure User Ping Pong!"))
                .andDo(print());
    }

    @Test
    @WithMockUser(username = "obaas-user", password = "password", roles = { "USER" })
    void asAObaasUser_shouldFailPingAdmin() throws Exception {
        mockMvc.perform(
                get("/user/api/v1/pingadmin"))
                .andExpect(status().is4xxClientError())
                .andDo(print());
    }
}
