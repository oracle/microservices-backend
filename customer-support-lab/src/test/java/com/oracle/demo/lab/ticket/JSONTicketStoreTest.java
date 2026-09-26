// Copyright (c) 2026, Oracle and/or its affiliates.
// Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

package com.oracle.demo.lab.ticket;

import com.oracle.spring.json.jsonb.JSONB;
import org.junit.jupiter.api.Test;

import java.sql.ResultSet;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class JSONTicketStoreTest {

    @Test
    void mapsSerializedDualityViewWithVector() throws Exception {
        ResultSet rs = mock(ResultSet.class);
        when(rs.getString(1)).thenReturn("""
                {"_id":42,"title":"Login issue","description":"Cannot log in",
                 "embedding":[0.1,0.2,0.3],
                 "relatedTickets":[{"relatedTicketId":7}]}
                """);

        SupportTicket ticket = new JSONTicketStore(null, JSONB.createDefault()).mapTextJson(rs, 0);

        assertThat(ticket.getId()).isEqualTo(42L);
        assertThat(ticket.getEmbedding()).containsExactly(0.1f, 0.2f, 0.3f);
        assertThat(ticket.getRelatedTickets())
                .extracting(RelatedTicket::getRelatedTicketId)
                .containsExactly(7L);
    }
}
