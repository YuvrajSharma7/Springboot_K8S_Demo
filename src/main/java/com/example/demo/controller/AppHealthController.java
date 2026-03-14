package com.example.demo.controller;

import lombok.extern.slf4j.Slf4j;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
@Slf4j
public class AppHealthController {

    @GetMapping("/health")
    public String healthCheck() {
        log.info("Health controller called");
        return "Application is healthy!";
    }
}
