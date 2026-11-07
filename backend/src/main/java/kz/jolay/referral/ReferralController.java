package kz.jolay.referral;

import kz.jolay.common.Auth;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/api/v1/customers/me/referral")
@PreAuthorize("hasRole('CUSTOMER')")
public class ReferralController {
    private final ReferralService referrals;
    public ReferralController(ReferralService referrals) { this.referrals = referrals; }

    @GetMapping
    public Map<String, Object> mine() { return referrals.summary(Auth.id()); }
}
