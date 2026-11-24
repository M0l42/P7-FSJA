package com.openclassroom.devops.orion.microcrm;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.support.TransactionTemplate;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Deleting an organization must only unlink its members, never delete them.
 * Bug found through the ELK logs: DELETE /organizations/{id} returned 500 (ConcurrentModificationException),
 * because the relationship cascaded the removal to the persons (CascadeType.ALL).
 */
@SpringBootTest
@AutoConfigureMockMvc
class OrganizationDeletionTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private OrganizationRepository organizationRepository;

    @Autowired
    private PersonRepository personRepository;

    @Autowired
    private TransactionTemplate tx;

    @Test
    void deletingAnOrganizationKeepsItsMembers() throws Exception {
        // Setup in one transaction: two persons, one of them also member of another organization
        long[] ids = tx.execute(status -> {
            Person ada = person("ada.deletion@example.net");
            Person alan = person("alan.deletion@example.net");
            Organization doomed = organization("Doomed Inc.", ada, alan);
            Organization other = organization("Other Inc.", alan);
            return new long[] { doomed.getId(), other.getId(), ada.getId(), alan.getId() };
        });
        long doomedId = ids[0], otherId = ids[1], adaId = ids[2], alanId = ids[3];

        mockMvc.perform(delete("/organizations/" + doomedId))
                .andExpect(status().is2xxSuccessful()); // 204, or 200 when the client sends an Accept header

        assertTrue(organizationRepository.findById(doomedId).isEmpty(), "the organization is deleted");
        assertTrue(personRepository.findById(adaId).isPresent(), "its members still exist");
        assertTrue(personRepository.findById(alanId).isPresent(), "its members still exist");
        Integer otherMembers = tx.execute(status -> organizationRepository.findById(otherId).orElseThrow().getPersons().size());
        assertEquals(1, otherMembers, "the other organization keeps its member");
    }

    @Test
    void deletingAPersonRemovesItFromItsOrganizations() throws Exception {
        long[] ids = tx.execute(status -> {
            Person grace = person("grace.deletion@example.net");
            Person linus = person("linus.deletion@example.net");
            Organization org = organization("Kept Inc.", grace, linus);
            return new long[] { org.getId(), grace.getId() };
        });
        long orgId = ids[0], graceId = ids[1];

        mockMvc.perform(delete("/persons/" + graceId))
                .andExpect(status().is2xxSuccessful());

        assertTrue(personRepository.findById(graceId).isEmpty(), "the person is deleted");
        Integer members = tx.execute(status -> organizationRepository.findById(orgId).orElseThrow().getPersons().size());
        assertEquals(1, members, "the organization still exists, without the deleted person");
    }

    private Person person(String email) {
        Person p = new Person();
        p.setEmail(email);
        return personRepository.save(p);
    }

    private Organization organization(String name, Person... members) {
        Organization org = new Organization();
        org.setName(name);
        for (Person member : members) {
            org.addPerson(member);
        }
        return organizationRepository.save(org);
    }
}
