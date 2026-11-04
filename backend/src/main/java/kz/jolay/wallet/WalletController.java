package kz.jolay.wallet;

import kz.jolay.common.Auth;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/wallet")
@PreAuthorize("hasAnyRole('CUSTOMER','DRIVER')")
public class WalletController {
    private final LedgerService ledger;
    public WalletController(LedgerService ledger) { this.ledger = ledger; }

    private UUID account() {
        var u = Auth.user();
        return ledger.userAccount(u.id(), u.has("DRIVER") ? "DRIVER_WALLET" : "CUSTOMER_WALLET");
    }

    @GetMapping
    public Map<String, Object> wallet() {
        UUID a = account();
        BigDecimal b = ledger.balance(a);
        return Map.of("balance", b, "currency", "KZT");
    }

    @GetMapping("/transactions")
    public List<Map<String, Object>> transactions(@RequestParam(defaultValue = "30") int limit, @RequestParam(defaultValue = "0") int offset) {
        return ledger.history(account(), limit, offset);
    }
}
