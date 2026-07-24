package main

import (
	"fmt"
	"os"

	"github.com/unified-finance/unified/services/foundation-ledger/internal/ledger"
)

func main() {
	if os.Getenv("UNIFIED_ENVIRONMENT") != "local" {
		fmt.Fprintln(os.Stderr, "foundation-ledger refuses to run outside UNIFIED_ENVIRONMENT=local")
		os.Exit(2)
	}
	_ = ledger.New()
	fmt.Println("foundation-ledger skeleton ready; no network listener or production behavior enabled")
}

