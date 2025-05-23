# Momentum-Building AI Suggestions Refactor

## Overview

This refactor enhances the InchForward app to track completed moves and use them as context for AI-generated suggestions, creating a momentum-building system that ensures actions progressively advance toward goals.

## Key Changes

### 1. Completed Moves Tracking

**New Methods in `GoalViewModel`:**
- `getLastThreeCompletedMoves()` - Retrieves the last 3 completed moves across all days
- `formatCompletedMovesForPrompt()` - Formats completed and existing moves for AI context
- `getCurrentExistingMoves()` - Gets current moves to avoid duplicates
- `getRecentCompletedMoves(limit:)` - Public method for UI display
- `getCompletedMovesDisplayText(limit:)` - Formatted text for display

### 2. Enhanced AI Prompts

**Context Inclusion:**
- Last 3 completed moves with titles and descriptions
- List of existing moves to prevent duplicates
- Enhanced system instruction emphasizing momentum building

**Example Enhanced Prompt:**
```
My current goal is: "Gain 10% Muscle Mass in 3 Months". Description: "Increase muscle mass...".

Recent completed moves (most recent first):
1. "Create a Weightlifting Program" - Design a weightlifting program focusing on...
2. "Design a High-Protein Diet" - Plan a high-protein diet to support muscle...
3. "Design Weightlifting Program" - Create a structured weightlifting program...

Existing moves already available:
1. "Design a Weightlifting Program"

Please suggest moves that build upon completed actions, create momentum toward the goal, and avoid duplicating existing moves.

Suggest 3-5 concise, actionable steps (moves) to help achieve this goal...
```

### 3. UI Enhancements

**GoalAndMoveView:**
- Added "RECENT PROGRESS" section showing completed moves
- Visual indicators with checkmarks and progress icons

**SwapMoveView:**
- Added "Builds on progress" indicator for AI suggestions
- Shows when suggestions are contextually aware of previous work

### 4. System Improvements

**Benefits:**
- ✅ Prevents duplicate move suggestions
- ✅ Creates logical progression of actions
- ✅ Builds momentum by acknowledging completed work
- ✅ Provides better user experience with relevant suggestions
- ✅ Enables compound progress toward goals

**Debug Features:**
- Console logging of completed moves included in AI context
- Tracking of moves count and titles for debugging

## Usage

The system automatically:
1. Tracks all completed moves via `DailyProgress` entries
2. Includes the last 3 completed moves in AI prompts
3. Avoids suggesting duplicate or similar actions
4. Creates suggestions that build upon previous work

No additional user action required - the momentum building happens automatically when generating new moves.

## Technical Implementation

**Data Flow:**
1. User completes a move → `recordDailyProgress()` stores it
2. AI suggestion request → `getLastThreeCompletedMoves()` retrieves context
3. Context formatted → `formatCompletedMovesForPrompt()` creates prompt text
4. Enhanced prompt sent → AI generates progressive suggestions
5. UI displays → Progress indicators show momentum awareness

**Storage:**
- Completed moves stored in `DailyProgress.moveCompleted`
- Linked to goals via relationships
- Sorted by date for chronological context
- No additional storage overhead

This refactor transforms the app from generating random suggestions to creating intelligent, progressive action sequences that build meaningful momentum toward goal achievement. 