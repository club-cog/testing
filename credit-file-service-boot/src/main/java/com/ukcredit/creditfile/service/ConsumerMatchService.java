package com.ukcredit.creditfile.service;

import com.ukcredit.common.NameNormaliser;
import com.ukcredit.creditfile.dao.ConsumerDao;
import com.ukcredit.creditfile.domain.Consumer;
import com.ukcredit.creditfile.rules.NameMatcher;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;

public class ConsumerMatchService {

    private final ConsumerDao consumerDao;
    private final NameMatcher nameMatcher;

    public ConsumerMatchService(ConsumerDao consumerDao, NameMatcher nameMatcher) {
        this.consumerDao = consumerDao;
        this.nameMatcher = nameMatcher;
    }

    public List<Consumer> match(String firstName, String surname, LocalDate dob) {
        String prefix = NameNormaliser.normalise(surname) + "|" + dob.format(DateTimeFormatter.BASIC_ISO_DATE) + "|";
        List<Consumer> out = new ArrayList<Consumer>();
        for (Consumer c : consumerDao.findCandidates(prefix)) {
            if (nameMatcher.matches(firstName, surname, dob, c.firstName, c.surname, c.dob)) {
                out.add(c);
            }
        }
        return out;
    }
}
