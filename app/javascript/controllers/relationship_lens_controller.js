import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "chain",
    "clearButton",
    "edge",
    "filterButton",
    "node",
    "selectionMeta",
    "selectionTitle",
    "visibleCount",
  ]

  connect() {
    this.filterType = "all"
    this.filterValue = "all"
    this.selectedNodeKey = null
    this.selectedChainId = null
    this.applyState()
  }

  filter(event) {
    this.filterType = event.currentTarget.dataset.filterType || "all"
    this.filterValue = event.currentTarget.dataset.filterValue || "all"
    this.selectedNodeKey = null
    this.selectedChainId = null
    this.applyState()
  }

  selectNode(event) {
    const node = event.currentTarget
    this.selectedNodeKey = node.dataset.nodeKey
    this.selectedChainId = null
    this.applyState({
      title: node.dataset.nodeLabel,
      meta: `${node.dataset.nodeRoleLabel || "Node"} · ${node.dataset.chainCount || "0"} chain(s)`,
    })
  }

  selectChain(event) {
    const card = event.currentTarget
    this.selectedChainId = card.dataset.chainId
    this.selectedNodeKey = null
    this.applyState({
      title: card.dataset.chainTitle,
      meta: `${card.dataset.chainSeverity || "chain"} · score ${card.dataset.chainScore || "?"}`,
    })
  }

  clear() {
    this.filterType = "all"
    this.filterValue = "all"
    this.selectedNodeKey = null
    this.selectedChainId = null
    this.applyState()
  }

  applyState(selection = null) {
    const visibleChains = []

    this.chainTargets.forEach((chain) => {
      const visible = this.chainMatchesFilter(chain) && this.chainMatchesSelection(chain)
      chain.classList.toggle("relationship-chain--hidden", !visible)
      chain.classList.toggle("relationship-chain--active", visible && this.selectedChainId === chain.dataset.chainId)
      if (visible) visibleChains.push(chain)
    })

    const activeChainIds = new Set(visibleChains.map((chain) => chain.dataset.chainId))
    const activeNodeKeys = new Set()
    visibleChains.forEach((chain) => {
      this.splitDataset(chain.dataset.nodeKeys).forEach((key) => activeNodeKeys.add(key))
    })

    this.nodeTargets.forEach((node) => {
      const active = activeNodeKeys.has(node.dataset.nodeKey)
      const selected = this.selectedNodeKey === node.dataset.nodeKey
      node.classList.toggle("relationship-node--dimmed", !active)
      node.classList.toggle("relationship-node--selected", selected)
      node.classList.toggle("relationship-node--active-path", active && (this.selectedNodeKey || this.selectedChainId))
    })

    this.edgeTargets.forEach((edge) => {
      const edgeChains = this.splitDataset(edge.dataset.chainIds)
      const active = edgeChains.some((chainId) => activeChainIds.has(chainId))
      edge.classList.toggle("relationship-edge--dimmed", !active)
      edge.classList.toggle("relationship-edge--active-path", active && (this.selectedNodeKey || this.selectedChainId))
    })

    this.filterButtonTargets.forEach((button) => {
      const active = (button.dataset.filterType || "all") === this.filterType
        && (button.dataset.filterValue || "all") === this.filterValue
      button.classList.toggle("relationship-filter--active", active)
    })

    this.updateSelectionSummary(selection, visibleChains.length)
  }

  chainMatchesFilter(chain) {
    if (this.filterType === "all") return true
    if (this.filterType === "kind") return chain.dataset.chainKind === this.filterValue
    if (this.filterType === "severity") return chain.dataset.chainSeverity === this.filterValue
    if (this.filterType === "corridor") return chain.dataset.chainCorridor === this.filterValue
    return true
  }

  chainMatchesSelection(chain) {
    if (this.selectedChainId) return chain.dataset.chainId === this.selectedChainId
    if (this.selectedNodeKey) return this.splitDataset(chain.dataset.nodeKeys).includes(this.selectedNodeKey)
    return true
  }

  updateSelectionSummary(selection, visibleCount) {
    const filterLabel = this.activeFilterLabel()
    const title = selection?.title || filterLabel || "All relationship chains"
    const meta = selection?.meta || `${visibleCount} visible chain${visibleCount === 1 ? "" : "s"}`

    this.selectionTitleTargets.forEach((target) => { target.textContent = title })
    this.selectionMetaTargets.forEach((target) => { target.textContent = meta })
    this.visibleCountTargets.forEach((target) => { target.textContent = visibleCount })
    this.clearButtonTargets.forEach((button) => {
      button.hidden = this.filterType === "all" && !this.selectedNodeKey && !this.selectedChainId
    })
  }

  activeFilterLabel() {
    if (this.filterType === "kind") return this.filterValue === "live" ? "Live driver chains" : "Structural chains"
    if (this.filterType === "severity") return `${this.filterValue} chains`
    if (this.filterType === "corridor") return this.filterValue
    return null
  }

  splitDataset(value) {
    return (value || "").split(" ").map((entry) => entry.trim()).filter(Boolean)
  }
}
