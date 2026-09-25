// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

package com.oracle.demo.lab.ticket;

import com.oracle.spring.json.jsonb.JSONB;
import jakarta.json.Json;
import jakarta.json.stream.JsonParser;
import oracle.jdbc.OracleTypes;
import org.springframework.context.annotation.Profile;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

import java.io.StringReader;
import java.sql.*;
import java.util.List;
import java.util.Optional;

@Component
@Profile("json")
public class JSONTicketStore implements TicketStore {
    private static final String UPDATE_SQL = """
            update ticket_dv v set data = ?
            where v.data."_id" = ?
            """;
    private static final String BY_ID_SQL = """
            select json_serialize(v.data returning clob) from ticket_dv v
            where v.data."_id" = ?
            """;
    private static final String ALL_SQL = """
            select json_serialize(v.data returning clob) from ticket_dv v
            """;

    private final JdbcClient jdbcClient;
    private final JSONB jsonb;
    private final RowMapper<SupportTicket> rowMapper;

    public JSONTicketStore(JdbcClient jdbcClient, JSONB jsonb) {
        this.jdbcClient = jdbcClient;
        this.jsonb = jsonb;
        this.rowMapper = this::mapTextJson;
    }

    SupportTicket mapTextJson(ResultSet rs, int rowNum) throws SQLException {
        // Text JSON exposes the duality view's native vector as a numeric array.
        try (JsonParser parser = Json.createParser(new StringReader(rs.getString(1)))) {
            return jsonb.fromOSON(parser, SupportTicket.class);
        }
    }

    @Override
    public void saveTicket(Connection conn, SupportTicket ticket) {
        byte[] oson = jsonb.toOSON(ticket);
        try (PreparedStatement ps = conn.prepareStatement(UPDATE_SQL)) {
            ps.setObject(1, oson, OracleTypes.JSON);
            ps.setLong(2, ticket.getId());
            ps.executeUpdate();
        } catch (SQLException e) {
            throw new RuntimeException(e);
        }
    }

    @Override
    public List<SupportTicket> getAllTickets() {
        return jdbcClient.sql(ALL_SQL)
                .query(rowMapper)
                .list();
    }

    @Override
    public Optional<SupportTicket> findById(Long id) {
        return jdbcClient.sql(BY_ID_SQL)
                .param(id)
                .query(rowMapper)
                .optional();
    }

    @Override
    public SupportTicket create(SupportTicket ticket) {
        throw new UnsupportedOperationException("Not implemented.");
    }

    @Override
    public void deleteAll() {
        jdbcClient.sql("truncate table related_ticket").update();
        jdbcClient.sql("truncate table support_ticket").update();
    }
}
