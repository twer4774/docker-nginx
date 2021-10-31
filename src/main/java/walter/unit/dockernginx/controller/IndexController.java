package walter.unit.dockernginx.controller;

import lombok.RequiredArgsConstructor;
import org.springframework.core.env.Environment;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

@RequiredArgsConstructor
@RestController
public class IndexController {


    private final Environment environment;

    @GetMapping("/index")
    public ResponseEntity<String> index(){
        System.out.println("commit을 위한 문구");
        return ResponseEntity.ok().body("index");
    }



}
