package com.example.ecommerce;

import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HealthController {
@GetMapping("/")
public Map<String, String> home() {
    return Map.of("service", "ecommerce-app", "status", "running");
}
}
