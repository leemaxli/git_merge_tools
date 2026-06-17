# Self-test of the harness primitives. These run under the harness itself.
Test-Case 'Assert-Equal passes on equal values' {
    Assert-Equal 3 (1 + 2)
}

Test-Case 'Assert-Equal throws on unequal values' {
    $threw = $false
    try { Assert-Equal 3 4 } catch { $threw = $true }
    Assert-True $threw 'Assert-Equal should have thrown'
}

Test-Case 'Assert-Match works' {
    Assert-Match 'refs/heads/\w+' 'refs/heads/main'
}

Test-Case 'KnownFail bug is recorded as expected-fail, not a hard failure' -KnownFail {
    Assert-True $false 'this documents a not-yet-fixed bug'
}
