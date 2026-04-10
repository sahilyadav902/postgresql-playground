package com.pgplayground;

import com.pgplayground.dto.UserRequest;
import com.pgplayground.entity.User;
import com.pgplayground.repository.UserRepository;
import com.pgplayground.service.UserService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class UserServiceTest {

    @Mock UserRepository userRepo;
    @InjectMocks UserService userService;

    private User alice;

    @BeforeEach
    void setUp() {
        alice = new User();
        alice.setEmail("alice@example.com");
        alice.setUsername("alice");
        alice.setDisplayName("Alice Smith");
        alice.setRole("customer");
    }

    @Test
    void findById_returnsUser_whenExists() {
        when(userRepo.findById(1L)).thenReturn(Optional.of(alice));
        User result = userService.findById(1L);
        assertThat(result.getEmail()).isEqualTo("alice@example.com");
    }

    @Test
    void findById_throws404_whenNotFound() {
        when(userRepo.findById(99L)).thenReturn(Optional.empty());
        assertThatThrownBy(() -> userService.findById(99L))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("User not found");
    }

    @Test
    void create_savesUser_whenEmailAndUsernameUnique() {
        when(userRepo.existsByEmail(anyString())).thenReturn(false);
        when(userRepo.existsByUsername(anyString())).thenReturn(false);
        when(userRepo.save(any(User.class))).thenReturn(alice);

        UserRequest req = new UserRequest();
        req.email = "alice@example.com";
        req.username = "alice";
        req.role = "customer";

        User result = userService.create(req);
        assertThat(result.getEmail()).isEqualTo("alice@example.com");
        verify(userRepo).save(any(User.class));
    }

    @Test
    void create_throwsConflict_whenEmailExists() {
        when(userRepo.existsByEmail("alice@example.com")).thenReturn(true);

        UserRequest req = new UserRequest();
        req.email = "alice@example.com";
        req.username = "alice";

        assertThatThrownBy(() -> userService.create(req))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("Email already exists");
        verify(userRepo, never()).save(any());
    }

    @Test
    void create_throwsConflict_whenUsernameExists() {
        when(userRepo.existsByEmail(anyString())).thenReturn(false);
        when(userRepo.existsByUsername("alice")).thenReturn(true);

        UserRequest req = new UserRequest();
        req.email = "new@example.com";
        req.username = "alice";

        assertThatThrownBy(() -> userService.create(req))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("Username already exists");
    }

    @Test
    void deactivate_setsActiveToFalse() {
        when(userRepo.findById(1L)).thenReturn(Optional.of(alice));
        when(userRepo.save(any(User.class))).thenReturn(alice);

        userService.deactivate(1L);

        assertThat(alice.isActive()).isFalse();
        verify(userRepo).save(alice);
    }

    @Test
    void addLoyaltyPoints_callsRepository() {
        when(userRepo.findById(1L)).thenReturn(Optional.of(alice));
        when(userRepo.addLoyaltyPoints(1L, 50)).thenReturn(1);

        int result = userService.addLoyaltyPoints(1L, 50);
        assertThat(result).isEqualTo(1);
        verify(userRepo).addLoyaltyPoints(1L, 50);
    }

    @Test
    void findAll_returnsAllUsers() {
        when(userRepo.findAll()).thenReturn(List.of(alice));
        List<User> result = userService.findAll();
        assertThat(result).hasSize(1);
    }
}
