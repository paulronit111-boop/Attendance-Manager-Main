
import streamlit as st
import pandas as pd
from supabase import create_client
from datetime import date
from io import BytesIO
from pathlib import Path


# ==================================================
# 1. PAGE CONFIGURATION
# ==================================================

# Use the same logo file throughout the app. Keep a fallback so the app
# still starts if logo.png has not yet been uploaded to the GitHub repository.
LOGO_PATH = Path(__file__).parent / "logo.png"

st.set_page_config(
    page_title="Gurucharan University | Statistics Department | Attendance",
    page_icon=str(LOGO_PATH) if LOGO_PATH.is_file() else "📊",
    layout="wide"
)

def show_department_branding():
    logo_col, title_col = st.columns([1, 5], vertical_alignment="center")
    with logo_col:
        if LOGO_PATH.is_file():
            st.image(str(LOGO_PATH), width=145)
        else:
            st.markdown("## 📊")
    with title_col:
        st.markdown("### Gurucharan University, Silchar")
        st.markdown("**Statistics Department**")
        st.caption("Attendance")

SEMESTERS = [
    "2nd Semester",
    "4th Semester",
    "6th Semester"
]

GROUPS = ["DSC", "DSM"]

SUBJECTS = {
    "DSC": {
        "2nd Semester": ["DSC 151", "DSC 152"],
        "4th Semester": ["DSC 251", "DSC 252", "DSC 253"],
        "6th Semester": ["DSC 351", "DSC 352", "DSC 353"]
    },
    "DSM": {
        "2nd Semester": ["DSM 151"],
        "4th Semester": ["DSM 251"],
        "6th Semester": ["DSM 351"]
    }
}

TEACHERS = ["SC", "SG", "MHB", "BB", "RP"]


# ==================================================
# 2. SUPABASE CONNECTION
# ==================================================

def get_supabase():

    if "supabase_client" not in st.session_state:

        url = st.secrets["SUPABASE_URL"]
        key = st.secrets["SUPABASE_KEY"]

        st.session_state.supabase_client = create_client(
            url,
            key
        )

    return st.session_state.supabase_client


try:
    sb = get_supabase()

except Exception as e:
    st.error(f"Supabase connection failed: {e}")
    st.stop()


# ==================================================
# 3. DATABASE HELPERS
# ==================================================

def get_rows(
    table,
    filters=None,
    start_date=None,
    end_date=None
):

    results = []
    offset = 0

    while True:

        query = sb.table(table).select("*")

        if filters:

            for column, value in filters.items():
                query = query.eq(column, value)

        if start_date is not None:
            query = query.gte(
                "attendance_date",
                str(start_date)
            )

        if end_date is not None:
            query = query.lte(
                "attendance_date",
                str(end_date)
            )

        response = query.range(
            offset,
            offset + 999
        ).execute()

        batch = response.data or []

        results.extend(batch)

        if len(batch) < 1000:
            break

        offset += 1000

    return results


def seed_subjects(owner_id):

    for group in GROUPS:

        for semester in SEMESTERS:

            for code in SUBJECTS[group][semester]:

                existing = (
                    sb.table("subjects")
                    .select("id")
                    .eq("owner_id", owner_id)
                    .eq("semester", semester)
                    .eq("code", code)
                    .execute()
                )

                if not existing.data:

                    sb.table("subjects").insert({
                        "owner_id": owner_id,
                        "semester": semester,
                        "code": code,
                        "student_group": group
                    }).execute()


def get_excel(dataframes):

    output = BytesIO()

    with pd.ExcelWriter(
        output,
        engine="openpyxl"
    ) as writer:

        for sheet_name, dataframe in dataframes.items():

            dataframe.to_excel(
                writer,
                index=False,
                sheet_name=sheet_name[:31]
            )

    output.seek(0)

    return output.getvalue()


# ==================================================
# 4. PRESENT / ABSENT CHECKBOX CONTROL
# ==================================================

def sync_attendance(
    present_key,
    absent_key,
    changed
):

    if changed == "present":

        if st.session_state[present_key]:
            st.session_state[absent_key] = False
        else:
            st.session_state[absent_key] = True

    else:

        if st.session_state[absent_key]:
            st.session_state[present_key] = False
        else:
            st.session_state[present_key] = True


# ==================================================
# 5. LOGIN AND REGISTRATION
# ==================================================

if "user_id" not in st.session_state:
    st.session_state.user_id = None


if not st.session_state.user_id:

    show_department_branding()
    st.subheader("Lecturer Attendance")

    login_tab, signup_tab = st.tabs([
        "Lecturer Login",
        "Create Account"
    ])

    # LOGIN

    with login_tab:

        email = st.text_input(
            "Email address",
            key="login_email"
        )

        password = st.text_input(
            "Password",
            type="password",
            key="login_password"
        )

        if st.button("Login", type="primary"):

            try:

                result = sb.auth.sign_in_with_password({
                    "email": email,
                    "password": password
                })

                if result.user:

                    st.session_state.user_id = result.user.id
                    st.rerun()

            except Exception as e:

                st.error(f"Login failed: {e}")

    # REGISTRATION

    with signup_tab:

        new_email = st.text_input(
            "Email address",
            key="signup_email"
        )

        new_password = st.text_input(
            "Create password",
            type="password",
            key="signup_password"
        )

        confirm_password = st.text_input(
            "Confirm password",
            type="password"
        )

        if st.button("Create Lecturer Account"):

            if not new_email or not new_password:

                st.warning(
                    "Enter your email and password."
                )

            elif new_password != confirm_password:

                st.error("Passwords do not match.")

            elif len(new_password) < 6:

                st.error(
                    "Password must contain at least 6 characters."
                )

            else:

                try:

                    result = sb.auth.sign_up({
                        "email": new_email,
                        "password": new_password
                    })

                    if result.session and result.user:

                        st.session_state.user_id = result.user.id
                        st.rerun()

                    else:

                        st.success(
                            "Registration submitted. Check your "
                            "email for verification, then log in."
                        )

                except Exception as e:

                    st.error(
                        f"Registration failed: {e}"
                    )

    st.stop()


# ==================================================
# 6. LOGGED-IN USER
# ==================================================

owner_id = st.session_state.user_id

try:

    seed_subjects(owner_id)

except Exception as e:

    st.error(f"Could not load subjects: {e}")
    st.stop()


show_department_branding()


# ==================================================
# 7. SIDEBAR NAVIGATION
# ==================================================

with st.sidebar:

    st.success("Lecturer logged in")

    page = st.radio(
        "Navigation",
        [
            "Dashboard",
            "Manage Students",
            "Mark Attendance",
            "Attendance Reports"
        ]
    )

    st.divider()

    if st.button("Logout"):

        try:
            sb.auth.sign_out()

        finally:

            st.session_state.user_id = None
            st.rerun()


# ==================================================
# 8. GROUP AND SEMESTER SELECTION USING CHECKBOXES
# ==================================================

def select_one(options, category, selected_option, reset_subjects=False):
    """
    Callback for checkbox groups.
    Exactly one option remains selected in each category.
    """
    selected_key = f"{category}_{selected_option}"

    # Keep the clicked checkbox selected.
    st.session_state[selected_key] = True

    # Uncheck the other options in this category.
    for option in options:
        key = f"{category}_{option}"
        if key != selected_key:
            st.session_state[key] = False

    # Clear the old subject selection when group or semester changes.
    # This callback runs before the widgets are created on the next rerun.
    if reset_subjects:
        for key in list(st.session_state.keys()):
            if key.startswith("subject_select_"):
                st.session_state[key] = False


# ---------------- GROUP CHECKBOXES ----------------

st.markdown("### Select Student Group")

group_cols = st.columns(len(GROUPS))

for i, group_option in enumerate(GROUPS):
    group_key = f"group_{group_option}"

    if group_key not in st.session_state:
        st.session_state[group_key] = (i == 0)

    with group_cols[i]:
        st.checkbox(
            group_option,
            key=group_key,
            on_change=select_one,
            args=(GROUPS, "group", group_option, True)
        )

group = next(
    (
        option for option in GROUPS
        if st.session_state.get(f"group_{option}", False)
    ),
    GROUPS[0]
)


# ---------------- SEMESTER CHECKBOXES ----------------

st.markdown("### Select Semester")

semester_cols = st.columns(len(SEMESTERS))

for i, semester_option in enumerate(SEMESTERS):
    semester_key = f"semester_{semester_option}"

    if semester_key not in st.session_state:
        st.session_state[semester_key] = (i == 0)

    with semester_cols[i]:
        st.checkbox(
            semester_option,
            key=semester_key,
            on_change=select_one,
            args=(SEMESTERS, "semester", semester_option, True)
        )

semester = next(
    (
        option for option in SEMESTERS
        if st.session_state.get(f"semester_{option}", False)
    ),
    SEMESTERS[0]
)

st.caption(f"Currently selected: {group} | {semester}")


# ==================================================
# 9. SUBJECT SELECTION USING CHECKBOXES
# ==================================================

subject_records = (
    sb.table("subjects")
    .select("*")
    .eq("owner_id", owner_id)
    .eq("semester", semester)
    .eq("student_group", group)
    .order("code")
    .execute()
).data or []

if not subject_records:
    st.warning("No subjects found for this group and semester.")
    st.stop()

subject_options = {
    item["code"]: item["id"]
    for item in subject_records
}

subject_list = list(subject_options.keys())

# Determine the currently selected subject before creating its widgets.
# If none is selected (for example, after changing group/semester),
# select the first available subject.
selected_subjects = [
    option for option in subject_list
    if st.session_state.get(f"subject_select_{option}", False)
]

if selected_subjects:
    selected_subject = selected_subjects[0]
else:
    selected_subject = subject_list[0]

# Initialize/reset subject widget values BEFORE creating the checkboxes.
for subject_option in subject_list:
    subject_key = f"subject_select_{subject_option}"
    if subject_key not in st.session_state or (
        selected_subjects and subject_option not in selected_subjects
    ):
        st.session_state[subject_key] = (
            subject_option == selected_subject
        )

# If multiple stale values existed, normalize them before widget creation.
for subject_option in subject_list:
    subject_key = f"subject_select_{subject_option}"
    if subject_option != selected_subject:
        st.session_state[subject_key] = False

st.markdown("### Select Subject")

subject_cols = st.columns(len(subject_list))

for i, subject_option in enumerate(subject_list):
    subject_key = f"subject_select_{subject_option}"

    with subject_cols[i]:
        st.checkbox(
            subject_option,
            key=subject_key,
            on_change=select_one,
            args=(subject_list, "subject_select", subject_option, False)
        )

subject_code = next(
    (
        option for option in subject_list
        if st.session_state.get(f"subject_select_{option}", False)
    ),
    subject_list[0]
)

subject_id = subject_options[subject_code]

st.caption(f"Selected Subject: {subject_code}")


# ==================================================
# 9A. RESET CLASS RECORDS FOR SELECTED SUBJECT
# ==================================================

with st.expander("⚠️ Reset Class Records for Selected Subject"):
    st.warning(
        f"This will permanently delete all class sessions and their "
        f"attendance entries for {group} – {semester} – {subject_code}. "
        "Student records will not be deleted. This action cannot be undone."
    )

    confirm_reset = st.checkbox(
        f"I confirm that I want to delete all class records for "
        f"{group} – {semester} – {subject_code}.",
        key=f"confirm_reset_{group}_{semester}_{subject_id}"
    )

    if st.button(
        "Reset Class Records",
        type="primary",
        key=f"reset_records_{group}_{semester}_{subject_id}",
        disabled=not confirm_reset
    ):
        try:
            # Fetch only this lecturer's sessions for the selected subject
            # and semester. Subject IDs are seeded separately per group.
            sessions_to_delete = get_rows(
                "class_sessions",
                {
                    "owner_id": owner_id,
                    "semester": semester,
                    "subject_id": subject_id
                }
            )

            session_ids_to_delete = [
                session["id"]
                for session in sessions_to_delete
            ]

            if not session_ids_to_delete:
                st.info("There are no class records to reset for this subject.")
            else:
                # Delete attendance entries linked to these sessions first.
                for session_id_to_delete in session_ids_to_delete:
                    (
                        sb.table("attendance")
                        .delete()
                        .eq("owner_id", owner_id)
                        .eq("session_id", session_id_to_delete)
                        .execute()
                    )

                # Then delete only the selected lecturer's matching sessions.
                for session_id_to_delete in session_ids_to_delete:
                    (
                        sb.table("class_sessions")
                        .delete()
                        .eq("owner_id", owner_id)
                        .eq("id", session_id_to_delete)
                        .execute()
                    )

                st.success(
                    f"Deleted {len(session_ids_to_delete)} class session(s) "
                    f"and their related attendance records for "
                    f"{group} – {semester} – {subject_code}."
                )
                st.rerun()

        except Exception as e:
            st.error(f"Could not reset class records: {e}")


# ==================================================
# 10. DASHBOARD
# ==================================================

if page == "Dashboard":

    st.header("Dashboard")

    students = get_rows(
        "students",
        {
            "owner_id": owner_id,
            "semester": semester,
            "student_group": group
        }
    )

    attendance = get_rows(
        "attendance",
        {
            "owner_id": owner_id,
            "subject_id": subject_id
        }
    )

    sessions = get_rows(
        "class_sessions",
        {
            "owner_id": owner_id,
            "semester": semester,
            "subject_id": subject_id
        }
    )

    col1, col2, col3 = st.columns(3)

    col1.metric(
        "Total Students",
        len(students)
    )

    col2.metric(
        "Classes Recorded",
        len(sessions)
    )

    col3.metric(
        "Attendance Entries",
        len(attendance)
    )

    st.divider()

    st.markdown("### Selected Group")

    st.write(f"**Group:** {group}")
    st.write(f"**Semester:** {semester}")

    st.markdown("### Subjects")

    for code in SUBJECTS[group][semester]:
        st.write("📘", code)


# ==================================================
# 11. MANAGE STUDENTS
# ==================================================

elif page == "Manage Students":

    st.header("Manage Students")

    st.info(
        f"Adding or editing students in: {group} – {semester}"
    )

    # ADD INDIVIDUAL STUDENT

    st.markdown("### Add Individual Student")

    with st.form("add_student_form"):

        roll_no = st.text_input("Roll Number")

        student_name = st.text_input("Student Name")

        add_button = st.form_submit_button(
            "Add Student"
        )

        if add_button:

            if roll_no.strip() and student_name.strip():

                try:

                    sb.table("students").upsert(
                        {
                            "owner_id": owner_id,
                            "semester": semester,
                            "student_group": group,
                            "roll_no": roll_no.strip(),
                            "name": student_name.strip()
                        },
                        on_conflict=(
                            "owner_id,semester,student_group,roll_no"
                        )
                    ).execute()

                    st.success(
                        "Student saved successfully!"
                    )

                    st.rerun()

                except Exception as e:

                    st.error(
                        f"Could not save student: {e}"
                    )

            else:

                st.warning(
                    "Enter both roll number and name."
                )

    st.divider()

    # IMPORT STUDENTS

    st.markdown("### Import Students from Excel or CSV")

    uploaded_file = st.file_uploader(
        "Upload student list",
        type=["xlsx", "xls", "csv"]
    )

    if uploaded_file is not None:

        try:

            if uploaded_file.name.lower().endswith(".csv"):

                df = pd.read_csv(
                    uploaded_file,
                    dtype=str,
                    keep_default_na=False
                )

            else:

                df = pd.read_excel(
                    uploaded_file,
                    dtype=str,
                    keep_default_na=False
                )

            df.columns = [
                str(column).strip().lower().replace(" ", "_")
                for column in df.columns
            ]

            st.write("Preview:")

            st.dataframe(
                df.head(10),
                use_container_width=True
            )

            if (
                "roll_no" not in df.columns
                or "name" not in df.columns
            ):

                st.warning(
                    "Your file must contain columns named "
                    "'roll_no' and 'name'."
                )

            elif st.button("Import Students"):

                df = df[
                    ["roll_no", "name"]
                ].drop_duplicates(
                    subset=["roll_no"]
                )

                records = []

                for _, row in df.iterrows():

                    roll = str(row["roll_no"]).strip()
                    name = str(row["name"]).strip()

                    if roll and name:

                        records.append({
                            "owner_id": owner_id,
                            "semester": semester,
                            "student_group": group,
                            "roll_no": roll,
                            "name": name
                        })

                if records:

                    sb.table("students").upsert(
                        records,
                        on_conflict=(
                            "owner_id,semester,student_group,roll_no"
                        )
                    ).execute()

                    st.success(
                        f"{len(records)} students imported "
                        f"into {group} – {semester}."
                    )

                    st.rerun()

                else:

                    st.warning(
                        "No valid student records found."
                    )

        except Exception as e:

            st.error(
                f"Import failed: {e}"
            )

    st.divider()

    # CURRENT STUDENT LIST

    st.markdown("### Current Student List")

    students = get_rows(
        "students",
        {
            "owner_id": owner_id,
            "semester": semester,
            "student_group": group
        }
    )

    if students:

        student_df = pd.DataFrame(students)

        display_df = student_df[
            ["roll_no", "name"]
        ].rename(
            columns={
                "roll_no": "Roll no",
                "name": "Name"
            }
        ).sort_values("Roll no")

        st.dataframe(
            display_df,
            use_container_width=True,
            hide_index=True
        )

        st.download_button(
            "Download Student List",
            data=get_excel({
                "Students": display_df
            }),
            file_name=f"{group}_{semester}_students.xlsx",
            mime=(
                "application/vnd.openxmlformats-officedocument."
                "spreadsheetml.sheet"
            )
        )

        st.divider()

        # EDIT OR DELETE

        st.markdown("### Edit or Delete Student")

        student_choices = {
            f'{s["roll_no"]} - {s["name"]}': s
            for s in students
        }

        selected_student = st.selectbox(
            "Choose Student",
            list(student_choices.keys())
        )

        chosen = student_choices[selected_student]

        with st.form("edit_student_form"):

            edit_roll = st.text_input(
                "Roll Number",
                value=chosen["roll_no"]
            )

            edit_name = st.text_input(
                "Student Name",
                value=chosen["name"]
            )

            update_button = st.form_submit_button(
                "Update Student"
            )

            if update_button:

                if not edit_roll.strip() or not edit_name.strip():

                    st.warning(
                        "Fields cannot be empty."
                    )

                else:

                    try:

                        sb.table("students").update(
                            {
                                "roll_no": edit_roll.strip(),
                                "name": edit_name.strip()
                            }
                        ).eq(
                            "id", chosen["id"]
                        ).eq(
                            "owner_id", owner_id
                        ).execute()

                        st.success("Student updated.")
                        st.rerun()

                    except Exception as e:

                        st.error(
                            f"Update failed: {e}"
                        )

        st.divider()

        st.warning(
            "Deleting a student will permanently delete "
            "their attendance history."
        )

        if st.button(
            "Delete Selected Student",
            type="primary"
        ):

            try:

                sb.table("attendance").delete().eq(
                    "student_id", chosen["id"]
                ).eq(
                    "owner_id", owner_id
                ).execute()

                sb.table("students").delete().eq(
                    "id", chosen["id"]
                ).eq(
                    "owner_id", owner_id
                ).execute()

                st.success("Student deleted.")
                st.rerun()

            except Exception as e:

                st.error(
                    f"Could not delete student: {e}"
                )

    else:

        st.info(
            f"No students added to {group} – {semester} yet."
        )


# ==================================================
# 12. MARK ATTENDANCE
# ==================================================

elif page == "Mark Attendance":

    st.header("Mark Class Attendance")

    attendance_date = st.date_input(
        "Select Class Date",
        value=date.today()
    )

    teacher = st.selectbox(
        "Select Teacher",
        TEACHERS
    )

    st.write(f"**Group:** {group}")
    st.write(f"**Semester:** {semester}")
    st.write(f"**Subject:** {subject_code}")
    st.write(f"**Teacher:** {teacher}")

    students = get_rows(
        "students",
        {
            "owner_id": owner_id,
            "semester": semester,
            "student_group": group
        }
    )

    if not students:

        st.warning(
            f"No students found in {group} – {semester}. "
            "Please add students first."
        )

    else:

        # FIND EXISTING CLASS SESSION

        sessions = get_rows(
            "class_sessions",
            {
                "owner_id": owner_id,
                "semester": semester,
                "class_date": str(attendance_date),
                "subject_id": subject_id,
                "teacher": teacher
            }
        )

        if len(sessions) > 1:

            st.error(
                "Multiple matching class sessions found. "
                "Please resolve the duplicate sessions."
            )

            st.stop()

        selected_session = (
            sessions[0] if sessions else None
        )

        session_id = (
            selected_session["id"]
            if selected_session
            else None
        )

        existing = []

        if session_id:

            existing = get_rows(
                "attendance",
                {
                    "owner_id": owner_id,
                    "session_id": session_id
                }
            )

        existing_status = {
            row["student_id"]: row["status"]
            for row in existing
        }

        st.divider()

        st.markdown("### Student Attendance Register")

        # TABLE HEADINGS

        header1, header2, header3 = st.columns(
            [1.2, 3, 2.5]
        )

        with header1:
            st.markdown("**Roll no**")

        with header2:
            st.markdown("**Name**")

        with header3:
            st.markdown("**Status (Present or Absent)**")

        st.divider()

        attendance_choices = {}

        # STUDENT ROWS

        for student in students:

            student_id = student["id"]

            previous_status = existing_status.get(
                student_id,
                "Present"
            )

            present_key = (
                f"present_{attendance_date}_{subject_id}_"
                f"{teacher}_{student_id}"
            )

            absent_key = (
                f"absent_{attendance_date}_{subject_id}_"
                f"{teacher}_{student_id}"
            )

            if present_key not in st.session_state:

                st.session_state[present_key] = (
                    previous_status == "Present"
                )

            if absent_key not in st.session_state:

                st.session_state[absent_key] = (
                    previous_status == "Absent"
                )

            # ENSURE EXACTLY ONE OPTION IS SELECTED

            if (
                st.session_state[present_key]
                == st.session_state[absent_key]
            ):

                st.session_state[present_key] = (
                    previous_status == "Present"
                )

                st.session_state[absent_key] = (
                    previous_status == "Absent"
                )

            row1, row2, row3 = st.columns(
                [1.2, 3, 2.5]
            )

            with row1:
                st.write(student["roll_no"])

            with row2:
                st.write(student["name"])

            with row3:

                present_col, absent_col = st.columns(2)

                with present_col:

                    st.checkbox(
                        "Present",
                        key=present_key,
                        on_change=sync_attendance,
                        args=(
                            present_key,
                            absent_key,
                            "present"
                        )
                    )

                with absent_col:

                    st.checkbox(
                        "Absent",
                        key=absent_key,
                        on_change=sync_attendance,
                        args=(
                            present_key,
                            absent_key,
                            "absent"
                        )
                    )

            attendance_choices[student_id] = (
                "Present"
                if st.session_state[present_key]
                else "Absent"
            )

            st.divider()

        # SAVE ATTENDANCE

        if st.button(
            "Save Class Attendance",
            type="primary"
        ):

            try:

                # CREATE SESSION AUTOMATICALLY

                if session_id is None:

                    session_result = (
                        sb.table("class_sessions")
                        .insert({
                            "owner_id": owner_id,
                            "semester": semester,
                            "subject_id": subject_id,
                            "class_date": str(attendance_date),
                            "teacher": teacher
                        })
                        .execute()
                    )

                    session_id = session_result.data[0]["id"]

                records = []

                for student in students:

                    student_id = student["id"]

                    records.append({
                        "owner_id": owner_id,
                        "student_id": student_id,
                        "subject_id": subject_id,
                        "attendance_date": str(attendance_date),
                        "session_id": session_id,
                        "status": attendance_choices[student_id]
                    })

                sb.table("attendance").upsert(
                    records,
                    on_conflict="owner_id,student_id,session_id"
                ).execute()

                st.success(
                    f"Attendance saved successfully for "
                    f"{group} – {semester} – {subject_code}!"
                )

                st.rerun()

            except Exception as e:

                st.error(
                    f"Could not save attendance: {e}"
                )


# ==================================================
# 13. ATTENDANCE REPORTS
# ==================================================

elif page == "Attendance Reports":

    st.header("Attendance Reports")

    st.write(
        f"**Group:** {group} | "
        f"**Semester:** {semester} | "
        f"**Subject:** {subject_code}"
    )

    col1, col2 = st.columns(2)

    with col1:

        start_date = st.date_input(
            "From Date",
            value=date(
                date.today().year,
                date.today().month,
                1
            ),
            key="report_start"
        )

    with col2:

        end_date = st.date_input(
            "To Date",
            value=date.today(),
            key="report_end"
        )

    if start_date > end_date:

        st.error(
            "Starting date cannot be after ending date."
        )

        st.stop()

    students = get_rows(
        "students",
        {
            "owner_id": owner_id,
            "semester": semester,
            "student_group": group
        }
    )

    attendance = get_rows(
        "attendance",
        {
            "owner_id": owner_id,
            "subject_id": subject_id
        },
        start_date=start_date,
        end_date=end_date
    )

    all_sessions = get_rows(
        "class_sessions",
        {
            "owner_id": owner_id,
            "semester": semester,
            "subject_id": subject_id
        }
    )

    sessions = [
        session for session in all_sessions
        if (
            str(start_date)
            <= session["class_date"]
            <= str(end_date)
        )
    ]

    session_ids = {
        session["id"]
        for session in sessions
    }

    total_classes = len(session_ids)

    attendance = [
        row for row in attendance
        if row.get("session_id") in session_ids
    ]

    if not students:

        st.info("No students available.")

    else:

        report_rows = []

        for student in students:

            student_records = [
                row for row in attendance
                if row["student_id"] == student["id"]
            ]

            present = sum(
                1 for row in student_records
                if row["status"] == "Present"
            )

            absent = sum(
                1 for row in student_records
                if row["status"] == "Absent"
            )

            percentage = (
                present / total_classes * 100
                if total_classes > 0
                else 0
            )

            report_rows.append({

                "Roll no": student["roll_no"],

                "Name": student["name"],

                "Present": present,

                "Absent": absent,

                "Total Classes": total_classes,

                "Attendance Percentage": round(
                    percentage,
                    2
                ),

                "Warning": (
                    "Below 75%"
                    if (
                        total_classes > 0
                        and percentage < 75
                    )
                    else "OK"
                )
            })

        report_df = pd.DataFrame(report_rows)

        st.metric(
            "Total Classes Recorded",
            total_classes
        )

        st.markdown("### Student-wise Attendance")

        st.dataframe(
            report_df,
            use_container_width=True,
            hide_index=True
        )

        # BELOW 75%

        st.markdown("### Students Below 75%")

        low_attendance = report_df[
            report_df["Warning"] == "Below 75%"
        ]

        if not low_attendance.empty:

            st.warning(
                f"{len(low_attendance)} student(s) "
                "are below 75% attendance."
            )

            st.dataframe(
                low_attendance,
                use_container_width=True,
                hide_index=True
            )

        else:

            st.success(
                "No students are below 75%."
            )

        st.divider()

        # MONTHLY SUMMARY

        st.markdown("### Monthly Attendance Summary")

        if attendance:

            monthly_df = pd.DataFrame(attendance)

            monthly_df["Month"] = pd.to_datetime(
                monthly_df["attendance_date"]
            ).dt.strftime("%B %Y")

            monthly_summary = (
                monthly_df.groupby(
                    ["Month", "status"]
                )
                .size()
                .unstack(fill_value=0)
                .reset_index()
            )

            st.dataframe(
                monthly_summary,
                use_container_width=True,
                hide_index=True
            )

        else:

            monthly_summary = pd.DataFrame()

            st.info(
                "No attendance records in this date range."
            )

        st.divider()

        # EXCEL EXPORT

        st.markdown("### Export Attendance Report")

        excel_sheets = {
            "Student Report": report_df
        }

        if not monthly_summary.empty:

            excel_sheets["Monthly Summary"] = monthly_summary

        st.download_button(
            "Download Attendance Report",
            data=get_excel(excel_sheets),
            file_name=(
                f"{group}_{semester}_{subject_code}_attendance.xlsx"
            ),
            mime=(
                "application/vnd.openxmlformats-officedocument."
                "spreadsheetml.sheet"
            )
        )


# ==================================================
# 14. FOOTER
# ==================================================

st.divider()

st.caption(
    "Gurucharan University, Silchar | Statistics Department | Attendance | "
    "Powered by Streamlit and Supabase"
)
