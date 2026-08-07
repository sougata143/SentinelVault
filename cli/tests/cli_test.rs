#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    fn sanitize_env_key(name: &str) -> String {
        name.chars()
            .map(|c| if c.is_alphanumeric() { c.to_ascii_uppercase() } else { '_' })
            .collect::<String>()
            .split('_')
            .filter(|s| !s.is_empty())
            .collect::<Vec<&str>>()
            .join("_")
    }

    fn parse_duration(s: &str) -> u64 {
        if s.ends_with('m') {
            s.trim_end_matches('m').parse::<u64>().unwrap_or(15) * 60
        } else if s.ends_with('h') {
            s.trim_end_matches('h').parse::<u64>().unwrap_or(1) * 3600
        } else if s.ends_with('s') {
            s.trim_end_matches('s').parse::<u64>().unwrap_or(900)
        } else {
            s.parse::<u64>().unwrap_or(900)
        }
    }

    #[test]
    fn test_sanitize_env_key() {
        assert_eq!(sanitize_env_key("Database Password"), "DATABASE_PASSWORD");
        assert_eq!(sanitize_env_key("stripe-api-key"), "STRIPE_API_KEY");
        assert_eq!(sanitize_env_key("  Redis Secret 123! "), "REDIS_SECRET_123");
    }

    #[test]
    fn test_parse_duration() {
        assert_eq!(parse_duration("15m"), 900);
        assert_eq!(parse_duration("1h"), 3600);
        assert_eq!(parse_duration("30s"), 30);
    }
}
