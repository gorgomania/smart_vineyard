// Подключается через node --import (bin/test-js): учит Node разрешать имена из importmap
import { register } from "node:module"

register("./importmap_hooks.mjs", import.meta.url)
