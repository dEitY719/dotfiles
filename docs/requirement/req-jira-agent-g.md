# JIRA Agent - Requirement Specification (Phase 1)

## 1. Overview
The JIRA Agent is an AI-powered service designed to simplify the creation of JIRA tickets. By leveraging Large Language Models (LLMs), it transforms unstructured inputs—such as meeting minutes, raw notes, or urgent messages—into structured JIRA Tasks and Sub-tasks. This service aims to reduce the administrative burden on developers in a team-centric JIRA environment.

## 2. Goal
- Automate JIRA ticket generation from natural language input.
- Ensure high-quality ticket metadata (summaries, descriptions, assignees) through AI processing.
- Provide a user-friendly web interface for reviewing and refining AI-generated tasks before creation.

## 3. Core Features (Phase 1)
- **AI Task Extraction**: Summarize meeting minutes or raw text into 2-3 actionable JIRA tasks.
- **Hierarchical Breakdown**: Automatically generate Sub-tasks for complex requirements.
- **Web Interface**: A frontend for users to input text, view proposed tickets, and confirm creation.
- **JIRA Integration**: Securely connect to JIRA via API (OAuth or PAT) to create issues.
- **Smart Mapping**: Default mapping of projects, components, and priorities based on input context.

## 4. Detailed Use Cases

### UC 1: Meeting Transcript to Action Items
- **User Story**: As a project manager, I want to paste a Zoom transcript into the agent so that I don't have to manually create tickets for every action item discussed.
- **Scenario**:
    1. User pastes a 10-page meeting transcript.
    2. AI identifies key decisions and assigned tasks (e.g., "Jane will update the API docs by Friday").
    3. AI proposes JIRA Tasks:
        - Title: Update API Documentation
        - Assignee: Jane
        - Due Date: Next Friday
        - Description: Extracted context from the meeting transcript.
    4. User reviews and clicks "Create All" on the web UI.

### UC 2: Urgent Slack Message to Task
- **User Story**: As a lead developer, I want to quickly turn an urgent Slack request into a JIRA task to ensure it is tracked properly.
- **Scenario**:
    1. User pastes: "Hey, the payment gateway is throwing 500 errors in production. We need to check the logs and fix it ASAP."
    2. AI identifies the urgency and the technical domain.
    3. AI proposes:
        - Title: [URGENT] Fix 500 errors in Payment Gateway
        - Priority: Highest
        - Labels: bug, production, payment
    4. User confirms and the ticket is created instantly.

### UC 3: Multi-Step Feature Implementation (Sub-tasks)
- **User Story**: As a developer, I want to break down a new feature request into sub-tasks automatically to manage my work better.
- **Scenario**:
    1. User inputs: "Implement a new user profile page with image upload and password reset."
    2. AI recognizes multiple components.
    3. AI proposes:
        - Parent Task: Implement User Profile Page
        - Sub-task 1: Design and implement UI layout
        - Sub-task 2: Implement image upload backend logic
        - Sub-task 3: Implement password reset flow
    4. User selects which sub-tasks to include and creates the hierarchy.

### UC 4: Interactive Review and Modification
- **User Story**: As a user, I want to tweak the AI's suggestions because AI is not always perfect.
- **Scenario**:
    1. AI generates a task title that is too generic.
    2. User edits the title in a text field on the web UI.
    3. User changes the assignee from a dropdown.
    4. User adds a label that the AI missed.
    5. User then submits the final version to JIRA.

### UC 5: Project & Component Auto-Detection
- **User Story**: As a user, I want the agent to know which JIRA project to use so I don't have to select it every time.
- **Scenario**:
    1. User inputs: "Fix the memory leak in the Mobile App."
    2. AI matches "Mobile App" to the "MOBILE" project in JIRA.
    3. AI sets the component to "Engine/Core".
    4. User sees the pre-filled project/component fields on the UI.

### UC 6: Smart Duplicate Detection (Early Phase 1)
- **User Story**: As a developer, I want to know if a similar task already exists so I don't create duplicates.
- **Scenario**:
    1. User inputs a bug description.
    2. AI searches recent JIRA tickets (using vector search or keyword matching).
    3. AI flags: "A similar ticket (BUG-123: Dashboard loading slow) already exists. Do you still want to create a new one?"
    4. User decides to update the existing ticket instead.

### UC 7: Priority Escalation for Security/Legal Issues
- **User Story**: As a security officer, I want the agent to automatically flag high-risk issues.
- **Scenario**:
    1. User inputs: "Found an unauthenticated API endpoint that leaks user emails."
    2. AI detects "unauthenticated", "leaks", and "emails".
    3. AI automatically sets Priority to "Blocker" and adds a "security-vulnerability" label.
    4. AI restricts the ticket visibility to the "Security-Team" (if supported by the JIRA project template).

### UC 8: Multi-Assignee Task Cloning
- **User Story**: As a team lead, I want to create the same task for multiple people at once.
- **Scenario**:
    1. User inputs: "Every developer needs to complete the mandatory security training."
    2. AI recognizes this is a group task.
    3. User selects 5 developers from the UI.
    4. Agent creates 5 separate JIRA tickets, one for each assignee, with the same description.

## 5. Technical Requirements (Brief)
- **Backend**: Python (FastAPI suggested).
- **AI**: OpenAI GPT-4o or Claude 3.5 Sonnet.
- **Frontend**: React or Dash Mantine Components.
- **Authentication**: JIRA Personal Access Token (PAT) for MVP; OAuth for broader rollout.

## 6. Phase 1 Constraints
- Focus on Task and Sub-task creation only (no Epics or Stories in Phase 1).
- No bidirectional sync (one-way creation from Agent to JIRA).
- Support for a limited number of pre-configured JIRA projects.

---
*Created by Gemini - Phase 1 Requirement*
