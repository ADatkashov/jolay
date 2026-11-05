package kz.jolay.admin;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/api/v1/admin/finance")
public class FinanceController {
    private final FinanceService finance;
    public FinanceController(FinanceService finance) { this.finance = finance; }

    @GetMapping("/reconciliation") @PreAuthorize("hasAnyRole('SUPER_ADMIN','FINANCE_ADMIN')")
    public Map<String, Object> reconciliation() { return finance.reconciliation(); }
}
