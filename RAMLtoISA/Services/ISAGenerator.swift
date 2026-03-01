import Foundation

/// Generates ISA (Integration Solution Architecture) markdown documents from parsed API specifications
final class ISAGenerator {

    private let apiInfo: APIInfo
    private let endpoints: [Endpoint]
    private let requirements: [Requirement]
    private let architect: String

    init(apiInfo: APIInfo, endpoints: [Endpoint], requirements: [Requirement], architect: String = "<architect.email@company.com>") {
        self.apiInfo = apiInfo
        self.endpoints = endpoints
        self.requirements = requirements
        self.architect = architect
    }

    // MARK: - Public

    func generateMarkdown() -> String {
        var sections: [String] = []

        sections.append(generateHeader())
        sections.append(generateIntroduction())
        sections.append(generateSolutionOverview())
        sections.append(generateArchitecture())

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Header

    private func generateHeader() -> String {
        let apiName = apiInfo.title
        let version = apiInfo.version
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy"
        let today = formatter.string(from: Date())

        return """
        # Integration Solution Architecture

        | **Project Name**              | \(apiName) |
        | ----------------------------- | ----------------------------------- |
        | **Document Version**          | \(version) |
        | **Document status**           | DRAFT |
        | **Date**                      | \(today) |
        | **Technical Architect**       | \(architect) |
        | **Requirement Specification** | \(apiName) |
        """
    }

    // MARK: - Introduction

    private func generateIntroduction() -> String {
        let apiName = apiInfo.title

        return """
        ## 1. Introduction

        ### 1.1 Purpose

        The purpose of this document is to describe the integration solution design for the **\(apiName)**.

        This document shall:

        - Communicate the end-to-end integration solution to all stakeholders
        - Provide traceability from API design to functional and non-functional requirements

        ### 1.2 Document Scope

        The scope of this document is limited to the approved functional and non-functional requirements derived from the \(apiName) OpenAPI specification and its exposed integration processes.

        ### 1.3 Definitions

        | **Term** | **Definition**                       |
        | -------- | ------------------------------------ |
        | API      | Application Programming Interface    |
        | OpenAPI  | REST API Specification Format        |
        | NFR      | Non-Functional Requirement           |
        | PII      | Personally Identifiable Information  |
        | MuleSoft | Integration platform hosting the API |
        """
    }

    // MARK: - Solution Overview

    private func generateSolutionOverview() -> String {
        var sections: [String] = []
        let apiName = apiInfo.title

        var overview = "## 2. Solution Overview\n\nThe \(apiName) is a MuleSoft-hosted REST API"

        if !endpoints.isEmpty {
            let endpointsList = endpoints.map { "- \($0.method) \($0.path): \($0.summary)" }.joined(separator: "\n")
            overview += "\n\nThe API provides:\n\n\(endpointsList)"
        }

        sections.append(overview)
        sections.append(generateSolutionScopeTable())
        sections.append(generateOutOfScope())
        sections.append(generateAssumptions())
        sections.append(generateConstraints())
        sections.append(generateDependencies())

        return sections.joined(separator: "\n\n")
    }

    private func generateSolutionScopeTable() -> String {
        let rows = endpoints.enumerated().map { (i, endpoint) in
            "| \(i + 1) | Global | \(endpoint.method) \(endpoint.path) | INT-STYL-13 API Management | Consumer Systems | MuleSoft API | FR-I-G-\(String(format: "%02d", i + 1)) | HIGH | Sync | Realtime | YES |"
        }.joined(separator: "\n")

        return """
        ### 2.1 Solution Scope

        | **Interface ID** | **Interface Region** | **Interface Name** | **Integration Style** | **Source Application** | **Target Application** | **Requirement ID** | **Business Criticality** | **Interface Type** | **Business Event** | **Reusable Asset?** |
        | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
        \(rows)
        """
    }

    private func generateOutOfScope() -> String {
        """
        ### 2.2 Out of Scope

        - Data mutation operations not explicitly defined in the specification
        - Conditional validation rules beyond schema validation
        - Custom UI or consumer-side pagination logic
        """
    }

    private func generateAssumptions() -> String {
        """
        ### 2.3 Assumptions

        - All consumers are registered in Anypoint Platform
        - Client credentials are securely managed by consuming systems
        - Underlying data sources are available and performant
        - API consumers have valid authentication credentials
        """
    }

    private func generateConstraints() -> String {
        var lines = ["### 2.4 Constraints\n"]

        // Find max page size from parameters
        var maxPageSize: Int?
        for ep in endpoints {
            for param in ep.parameters {
                if param.name == "pageSize", let max = param.maximum {
                    maxPageSize = max
                    break
                }
            }
        }

        if let maxPageSize {
            lines.append("- Page size is limited to a maximum of \(maxPageSize) records")
        }

        let methods = Set(endpoints.map(\.method)).sorted().joined(separator: ", ")
        lines.append("- API access is restricted via authentication enforcement")
        lines.append("- Only \(methods) operations are supported")

        return lines.joined(separator: "\n")
    }

    private func generateDependencies() -> String {
        """
        ### 2.5 Dependencies

        - MuleSoft Anypoint Runtime availability
        - Underlying data source availability and performance
        - API Manager policies for authentication and logging
        """
    }

    // MARK: - Architecture

    private func generateArchitecture() -> String {
        var sections = ["## 3. Integration Solution Architecture"]

        sections.append("### 3.1 Logical Interaction\n")
        sections.append(generateLogicalInteractionDiagram())

        sections.append("### 3.2 Sequence Diagram\n")
        sections.append(generateSequenceDiagram())

        sections.append(generateEndpointSpecifications())
        sections.append(generateApplicationInteractionMatrix())
        sections.append(generateSecurityMonitoring())
        sections.append(generateRequirementsSection())

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Mermaid Diagrams

    private func generateLogicalInteractionDiagram() -> String {
        """
        ```mermaid
        flowchart LR
            Consumer["Consuming System"]
            API["\(apiInfo.title)"]
            Data["Reference Data Source"]

            Consumer -->|HTTPS + Auth| API
            API --> Data
            Data --> API
            API -->|JSON Response| Consumer
        ```
        """
    }

    private func generateSequenceDiagram() -> String {
        let mainEndpoint = endpoints.first(where: { $0.method == "GET" && $0.path != "/" }) ?? endpoints.first

        guard let ep = mainEndpoint else { return "" }

        let params = ep.parameters.map(\.name).joined(separator: "&")

        return """
        ```mermaid
        sequenceDiagram
            participant C as Consumer
            participant M as MuleSoft API
            participant D as Reference Data Source

            C->>M: \(ep.method) \(ep.path)?\(params)
            M->>M: Authentication & Authorization
            M->>D: Fetch data with filters
            D-->>M: Data records
            M-->>C: 200 OK (Response)
        ```
        """
    }

    // MARK: - Endpoint Specifications

    private func generateEndpointSpecifications() -> String {
        guard !endpoints.isEmpty else { return "" }

        let section = "### 3.3 API Endpoints\n\n"
        var specs: [String] = []

        for endpoint in endpoints {
            var spec = "#### \(endpoint.method) \(endpoint.path)\n\n"
            spec += "**Summary:** \(endpoint.summary)\n\n"
            spec += "**Description:** \(endpoint.description)\n\n"
            spec += "**Parameters:**\n"

            if !endpoint.parameters.isEmpty {
                for param in endpoint.parameters {
                    let required = param.required ? "Required" : "Optional"
                    spec += "\n- `\(param.name)` (\(required)): \(param.description)"
                    if let example = param.example {
                        spec += " (e.g., `\(example)`)"
                    }
                }
            } else {
                spec += "\nNone"
            }

            spec += "\n\n**Responses:**\n"
            for resp in endpoint.responses {
                spec += "\n- **\(resp.statusCode)**: \(resp.description)"
            }

            specs.append(spec)
        }

        return section + specs.joined(separator: "\n\n")
    }

    // MARK: - Interaction Matrix

    private func generateApplicationInteractionMatrix() -> String {
        var section = """
        ### 3.4 Application Interaction Matrix

        | **Interface ID** | **Source App** | **Source Domain** | **Source Format** | **Target App** | **Target Domain** | **Target Format** | **Data Class** | **Business Criticality** | **SLA** | **Complexity** |
        | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

        """

        for i in 0..<endpoints.count {
            section += "| \(i + 1) | Consumer Systems | External | N/A | \(apiInfo.title) | Cloud | JSON | Confidential | HIGH | Medium |\n"
        }

        return section
    }

    // MARK: - Security & Monitoring

    private func generateSecurityMonitoring() -> String {
        var securityInfo = "### 3.5 Security and Monitoring\n\n#### Authentication\n\n"

        if !apiInfo.securitySchemes.isEmpty {
            for (name, scheme) in apiInfo.securitySchemes {
                let desc = scheme.description.isEmpty ? scheme.scheme : scheme.description
                securityInfo += "- **\(name)**: \(desc.isEmpty ? "Unknown" : desc)\n"
            }
        } else {
            securityInfo += "- Standard authentication mechanisms via MuleSoft API Manager\n"
        }

        securityInfo += """

        #### Authorization

        - Access controlled by registered consumer applications
        - Role-based access control enforced at API Manager level

        #### Monitoring & Logging

        - Request/response logging with sensitive field masking
        - Error logging for 4xx and 5xx responses
        - Performance metrics tracking

        #### Error Handling

        - Standard HTTP status codes returned
        - Consistent error response format
        - Detailed error messages for debugging

        #### Availability & Resilience

        - Stateless API design supporting horizontal scaling
        - Connection pooling and retry mechanisms
        - Circuit breaker patterns for dependency resilience
        """

        return securityInfo
    }

    // MARK: - Requirements

    private func generateRequirementsSection() -> String {
        guard !requirements.isEmpty else { return "" }

        var section = "### 3.6 Requirements Traceability\n\n"

        let frList = requirements.filter { $0.reqType == .functional }
        if !frList.isEmpty {
            section += "#### Functional Requirements\n\n"
            section += "| **ID** | **Use Case** | **Description** | **Acceptance Criteria** |\n"
            section += "| --- | --- | --- | --- |\n"
            for req in frList {
                section += "| \(req.reqId) | \(req.useCase) | \(req.description) | \(req.acceptanceCriteria) |\n"
            }
            section += "\n"
        }

        let nfrList = requirements.filter { $0.reqType == .nonFunctional }
        if !nfrList.isEmpty {
            section += "#### Non-Functional Requirements\n\n"
            section += "| **ID** | **Category** | **Description** |\n"
            section += "| --- | --- | --- |\n"
            for req in nfrList {
                section += "| \(req.reqId) | \(req.useCase) | \(req.description) |\n"
            }
        }

        return section
    }
}
