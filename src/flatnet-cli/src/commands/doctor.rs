//! Doctor command implementation
//!
//! Runs system diagnostics and reports issues with suggestions.

use anyhow::Result;
use colored::Colorize;
use serde::Serialize;
use std::collections::HashMap;
use std::process::ExitCode;

use crate::checks::{self, calculate_summary, determine_exit_code, CheckResult, CheckStatus};
use crate::cli::DoctorArgs;
use crate::config::Config;

/// Check symbols for display
const CHECK_PASS: &str = "\u{2713}"; // ✓
const CHECK_WARN: &str = "!";
const CHECK_FAIL: &str = "\u{2717}"; // ✗

/// Summary line character
const SUMMARY_LINE: &str = "\u{2501}"; // ━

/// JSON output structure
#[derive(Debug, Clone, Serialize)]
struct DoctorOutput {
    checks: Vec<CheckResult>,
    summary: SummaryOutput,
}

#[derive(Debug, Clone, Serialize)]
struct SummaryOutput {
    passed: usize,
    warnings: usize,
    failed: usize,
    exit_code: i32,
}

/// Run the doctor command
pub async fn run(args: DoctorArgs) -> Result<ExitCode> {
    let config = Config::load()?;

    if !args.quiet && !args.json {
        println!();
        println!("{}", "Running system diagnostics...".bold());
        println!();
    }

    // Run all checks
    let results = checks::run_all_checks(&config).await;

    // Calculate summary
    let (passed, warnings, failed) = calculate_summary(&results);
    let exit_code = determine_exit_code(&results);

    // Output results
    if args.json {
        print_json_output(&results, passed, warnings, failed, exit_code)?;
    } else if args.quiet {
        print_quiet_output(&results, config.color_enabled());
    } else {
        print_formatted_output(&results, args.verbose, config.color_enabled());
        print_summary(passed, warnings, failed, config.color_enabled());
    }

    // Return appropriate exit code
    Ok(match exit_code {
        0 => ExitCode::SUCCESS,
        1 => ExitCode::from(1),
        _ => ExitCode::from(2),
    })
}

/// Print results in JSON format
fn print_json_output(
    results: &[CheckResult],
    passed: usize,
    warnings: usize,
    failed: usize,
    exit_code: i32,
) -> Result<()> {
    let output = DoctorOutput {
        checks: results.to_vec(),
        summary: SummaryOutput {
            passed,
            warnings,
            failed,
            exit_code,
        },
    };

    let json = serde_json::to_string_pretty(&output)?;
    println!("{}", json);
    Ok(())
}

/// Print only issues (quiet mode for CI)
fn print_quiet_output(results: &[CheckResult], use_color: bool) {
    for result in results {
        if result.status != CheckStatus::Pass {
            let status_str = match result.status {
                CheckStatus::Warning => "WARN",
                CheckStatus::Fail => "FAIL",
                CheckStatus::Pass => continue, // Skip pass (unreachable due to outer condition)
            };

            if use_color {
                let status_colored = match result.status {
                    CheckStatus::Warning => status_str.yellow(),
                    CheckStatus::Fail => status_str.red(),
                    CheckStatus::Pass => continue, // Skip pass
                };
                println!(
                    "[{}] {}/{}: {}",
                    status_colored, result.category, result.name, result.message
                );
            } else {
                println!(
                    "[{}] {}/{}: {}",
                    status_str, result.category, result.name, result.message
                );
            }

            if let Some(ref suggestion) = result.suggestion {
                println!("  -> {}", suggestion);
            }
        }
    }
}

/// Print formatted output with categories
fn print_formatted_output(results: &[CheckResult], verbose: bool, use_color: bool) {
    // Group results by category
    let mut categories: HashMap<String, Vec<&CheckResult>> = HashMap::new();
    for result in results {
        categories
            .entry(result.category.clone())
            .or_default()
            .push(result);
    }

    // Define category order
    let category_order = ["Gateway", "CNI Plugin", "Network", "Monitoring", "Disk"];

    for category in category_order.iter() {
        if let Some(checks) = categories.get(*category) {
            print_category(category, checks, verbose, use_color);
        }
    }

    // Print any remaining categories not in the order (sorted for consistent output)
    let mut remaining: Vec<_> = categories
        .iter()
        .filter(|(cat, _)| !category_order.contains(&cat.as_str()))
        .collect();
    remaining.sort_by_key(|(cat, _)| cat.as_str());

    for (category, checks) in remaining {
        print_category(category, checks, verbose, use_color);
    }
}

/// Print a single category's results
fn print_category(category: &str, checks: &[&CheckResult], verbose: bool, use_color: bool) {
    // Print category header
    if use_color {
        println!("{}", category.bold());
    } else {
        println!("{}", category);
    }

    // Print each check
    for check in checks {
        print_check_result(check, verbose, use_color);
    }

    println!();
}

/// Print a single check result
fn print_check_result(result: &CheckResult, verbose: bool, use_color: bool) {
    let symbol = match result.status {
        CheckStatus::Pass => {
            if use_color {
                CHECK_PASS.green().to_string()
            } else {
                CHECK_PASS.to_string()
            }
        }
        CheckStatus::Warning => {
            if use_color {
                CHECK_WARN.yellow().to_string()
            } else {
                CHECK_WARN.to_string()
            }
        }
        CheckStatus::Fail => {
            if use_color {
                CHECK_FAIL.red().to_string()
            } else {
                CHECK_FAIL.to_string()
            }
        }
    };

    // Format the message - show details for non-pass or in verbose mode
    let message = if verbose || result.status != CheckStatus::Pass {
        &result.message
    } else {
        &result.name
    };

    if use_color {
        let message_colored = match result.status {
            CheckStatus::Pass => message.normal(),
            CheckStatus::Warning => message.yellow(),
            CheckStatus::Fail => message.red(),
        };
        println!("  [{}] {}", symbol, message_colored);
    } else {
        println!("  [{}] {}", symbol, message);
    }

    // Print suggestion for warnings and failures
    if result.status != CheckStatus::Pass {
        if let Some(ref suggestion) = result.suggestion {
            if use_color {
                println!("      {} {}", "\u{2192}".dimmed(), suggestion.dimmed());
            } else {
                println!("      -> {}", suggestion);
            }
        }
    }
}

/// Print the summary line
fn print_summary(passed: usize, warnings: usize, failed: usize, use_color: bool) {
    // Print separator line
    let line = SUMMARY_LINE.repeat(51);
    if use_color {
        println!("{}", line.bright_black());
    } else {
        println!("{}", line);
    }

    // Build summary parts
    let passed_str = format!("{} passed", passed);
    let warnings_str = format!("{} warnings", warnings);
    let failed_str = format!("{} failed", failed);

    if use_color {
        let passed_colored = passed_str.green();
        let warnings_colored = if warnings > 0 {
            warnings_str.yellow()
        } else {
            warnings_str.normal()
        };
        let failed_colored = if failed > 0 {
            failed_str.red()
        } else {
            failed_str.normal()
        };
        println!(
            "Summary: {}, {}, {}",
            passed_colored, warnings_colored, failed_colored
        );
    } else {
        println!("Summary: {}, {}, {}", passed_str, warnings_str, failed_str);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_summary_output_serialize() {
        let summary = SummaryOutput {
            passed: 5,
            warnings: 2,
            failed: 1,
            exit_code: 2,
        };

        let json = serde_json::to_string(&summary).unwrap();
        assert!(json.contains("\"passed\":5"));
        assert!(json.contains("\"warnings\":2"));
        assert!(json.contains("\"failed\":1"));
        assert!(json.contains("\"exit_code\":2"));
    }
}
